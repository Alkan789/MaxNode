#!/bin/bash

# --- 1. SİSTEM AYARLARI ---
export NODE_NAME="sys-update-daemon"
# (Tmate'i kaldırıyoruz, log okuma sistemine geçiyoruz çünkü Tmate 503 veriyor)

# --- 2. GOOGLE DRIVE ---
mkdir -p ~/.config/rclone
echo "[gdrive]
type = drive
token = $RCLONE_TOKEN_BODY" > ~/.config/rclone/rclone.conf
rclone mkdir gdrive:hemi_backup || true
rclone copy gdrive:hemi_backup/popm_address.json . || echo "Yedek yok."

# --- 3. HEMI KURULUM ---
if [ ! -f "./popmd" ]; then
    wget -q https://github.com/hemilabs/heminetwork/releases/download/v0.4.3/heminetwork_v0.4.3_linux_amd64.tar.gz
    tar -xf heminetwork_v0.4.3_linux_amd64.tar.gz
    cp heminetwork_v0.4.3_linux_amd64/popmd .
    chmod +x popmd
fi

# --- 4. CÜZDAN VE ADRES TESPİTİ ---
if [ ! -f "./popm_address.json" ]; then
    PRIV_HEX=$(openssl rand -hex 32)
    echo "{\"private_key\":\"$PRIV_HEX\",\"pubkey_hash\":\"generating...\"}" > popm_address.json
    rclone copy popm_address.json gdrive:hemi_backup/ --overwrite
fi

export POPM_BTC_PRIVKEY=$(cat popm_address.json | jq -r '.private_key')
export POPM_STATIC_FEE=50
export POPM_BFG_URL="wss://testnet.rpc.hemi.network/v1/ws/public"

# --- 5. MADENCİ BAŞLAT (LOGLARI KAYDET) ---
# Logları miner.log dosyasına yazdırıyoruz
./popmd > miner.log 2>&1 &

# Adresin loglara düşmesi için 10 saniye bekle
sleep 10

# Loglardan adresi cımbızla çek
DETECTED_ADDR=$(grep -oE "m[a-zA-Z0-9]{30,}" miner.log | head -n 1)

# Eğer adres bulunduysa JSON dosyasını güncelle
if [ ! -z "$DETECTED_ADDR" ]; then
    echo "Adres Bulundu: $DETECTED_ADDR"
    # JSON'ı güncelle
    jq --arg addr "$DETECTED_ADDR" '.pubkey_hash = $addr' popm_address.json > tmp.json && mv tmp.json popm_address.json
    rclone copy popm_address.json gdrive:hemi_backup/ --overwrite
else
    # Bulunamazsa yedekteki adresi kullan
    DETECTED_ADDR=$(cat popm_address.json | jq -r '.pubkey_hash')
fi

# --- 6. İZLEME DÖNGÜSÜ ---
START_TIME=$SECONDS
while [ $((SECONDS - START_TIME)) -lt 19800 ]; do 
    CPU=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Son 10 satır logu oku ve şifrele (URL bozulmasın diye base64 yapıyoruz)
    LOGS=$(tail -n 10 miner.log | base64 -w 0)
    
    # Miysoft'a gönder
    curl -s -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"W_$WORKER_ID\", \"cpu\":\"$CPU\", \"ram\":\"$RAM\", \"address\":\"$DETECTED_ADDR\", \"status\":\"HEMI_MINING\", \"logs\":\"$LOGS\"}" \
         https://miysoft.com/api.php || true
    
    sleep 30
done

# --- 7. KAPANIŞ ---
pkill popmd
rclone copy popm_address.json gdrive:hemi_backup/ --overwrite

TARGET_REPO=$([ "$GITHUB_REPOSITORY" == "Alkan789/MaxNode" ] && echo "Alkan789/MadNode" || echo "Alkan789/MaxNode")
curl -X POST -H "Authorization: token $PAT_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/$TARGET_REPO/dispatches \
     -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$((WORKER_ID + 1))\"}}"
