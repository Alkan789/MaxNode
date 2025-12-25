#!/bin/bash

# --- 1. SİSTEM AYARLARI ---
export NODE_NAME="sys-update-daemon"

# --- 2. GOOGLE DRIVE AYARLARI ---
mkdir -p ~/.config/rclone
echo "[gdrive]
type = drive
token = $RCLONE_TOKEN_BODY" > ~/.config/rclone/rclone.conf

# Klasör yoksa oluştur, varsa geç
rclone mkdir gdrive:hemi_backup || true

# Önceki cüzdanı çek
rclone copy gdrive:hemi_backup/popm_address.json . || echo "Yedek yok."

# --- 3. HEMI BINARY KURULUM ---
if [ ! -f "./popmd" ]; then
    wget -q https://github.com/hemilabs/heminetwork/releases/download/v0.4.3/heminetwork_v0.4.3_linux_amd64.tar.gz
    tar -xf heminetwork_v0.4.3_linux_amd64.tar.gz
    cp heminetwork_v0.4.3_linux_amd64/popmd .
    chmod +x popmd
fi

# --- 4. CÜZDAN OLUŞTURMA VE ADRES TESPİTİ ---
if [ ! -f "./popm_address.json" ]; then
    # Manuel Private Key Üretimi
    PRIV_HEX=$(openssl rand -hex 32)
    echo "{\"private_key\":\"$PRIV_HEX\",\"pubkey_hash\":\"generating...\"}" > popm_address.json
    
    # Hemen yedekle (Bayraksız, düz copy)
    rclone copy popm_address.json gdrive:hemi_backup/
fi

# Ortam Değişkenlerini Ayarla
export POPM_BTC_PRIVKEY=$(cat popm_address.json | jq -r '.private_key')
export POPM_STATIC_FEE=50
export POPM_BFG_URL="wss://testnet.rpc.hemi.network/v1/ws/public"

# --- 5. MADENCİ BAŞLAT (LOGLARI KAYDET) ---
# Logları miner.log dosyasına yazdırıyoruz
./popmd > miner.log 2>&1 &

# Adresin loglara düşmesi için 15 saniye bekle
sleep 15

# Loglardan adresi cımbızla çek (m harfiyle başlayan uzun dizi)
DETECTED_ADDR=$(grep -oE "m[a-zA-Z0-9]{30,}" miner.log | head -n 1)

# Eğer adres bulunduysa JSON dosyasını güncelle ve panele yansıt
if [ ! -z "$DETECTED_ADDR" ]; then
    echo "Adres Tespit Edildi: $DETECTED_ADDR"
    # JSON'ı güncelle
    jq --arg addr "$DETECTED_ADDR" '.pubkey_hash = $addr' popm_address.json > tmp.json && mv tmp.json popm_address.json
    # Güncel hali yedekle
    rclone copy popm_address.json gdrive:hemi_backup/
else
    # Bulunamazsa yedekteki adresi kullan (veya generating yazsın)
    DETECTED_ADDR=$(cat popm_address.json | jq -r '.pubkey_hash')
fi

# --- 6. İZLEME DÖNGÜSÜ ---
START_TIME=$SECONDS
while [ $((SECONDS - START_TIME)) -lt 19800 ]; do 
    CPU=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Son 15 satır logu oku ve şifrele (URL bozulmasın diye base64 yapıyoruz)
    LOGS=$(tail -n 15 miner.log | base64 -w 0)
    
    # Miysoft'a gönder
    curl -s -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"W_$WORKER_ID\", \"cpu\":\"$CPU\", \"ram\":\"$RAM\", \"address\":\"$DETECTED_ADDR\", \"status\":\"HEMI_MINING\", \"logs\":\"$LOGS\"}" \
         https://miysoft.com/api.php || true
    
    sleep 30
done

# --- 7. KAPANIŞ ---
pkill popmd
# Son kez yedekle (Bayraksız)
rclone copy popm_address.json gdrive:hemi_backup/

TARGET_REPO=$([ "$GITHUB_REPOSITORY" == "Alkan789/MaxNode" ] && echo "Alkan789/MadNode" || echo "Alkan789/MaxNode")
curl -X POST -H "Authorization: token $PAT_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/$TARGET_REPO/dispatches \
     -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$((WORKER_ID + 1))\"}}"
