#!/bin/bash

# --- 1. GİZLİLİK VE SSH AYARI ---
export NODE_NAME="sys-update-daemon"
# Şifre boşsa varsayılan bir şifre belirleyelim ki hata vermesin
USER_PASS=${SSH_PASSWORD:-"Miysoft1234!"}

sudo useradd -m -s /bin/bash miysoft || echo "Kullanıcı zaten var"
echo "miysoft:$USER_PASS" | sudo chpasswd || echo "Şifre değiştirilemedi ama devam ediliyor..."
sudo usermod -aG sudo miysoft

# --- 2. CLOUDFLARE SSH TÜNELİ ---
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O cloudflared
chmod +x cloudflared
./cloudflared tunnel --url tcp://localhost:22 > cf.log 2>&1 &
sleep 15
SSH_URL=$(grep -oE "https://[a-zA-Z0-9.-]+\.trycloudflare\.com" cf.log | head -n 1)

# --- 3. GOOGLE DRIVE VE RCLONE AYARI ---
mkdir -p ~/.config/rclone
echo "[gdrive]
type = drive
token = $RCLONE_TOKEN_BODY" > ~/.config/rclone/rclone.conf

# --- 4. CÜZDAN KİMLİK (IDENTITY) YÖNETİMİ ---
# Google Drive'da klasör yoksa hata vermemesi için sessizce kontrol et
rclone copy gdrive:avail_backup/identity.json . || echo "Henüz yedek yok, ilk kez oluşturulacak."

# --- 5. AVAIL LIGHT CLIENT İNDİR VE ÇALIŞTIR ---
wget -q https://github.com/availproject/avail-light/releases/download/v1.7.10/avail-light-linux-amd64.tar.gz
tar -xf avail-light-linux-amd64.tar.gz
mv avail-light-linux-amd64 $NODE_NAME
chmod +x $NODE_NAME

# DÜZELTME: Ağ ismini 'turing' (ekran görüntündeki ağ) yapıyoruz
# Ayrıca identity.json yoksa hata almamak için kontrol ekledik
./$NODE_NAME --network turing --identity ./identity.json $([ ! -z "$AVAIL_MNEMONIC" ] && echo "--seed \"$AVAIL_MNEMONIC\"") &

# --- 6. İZLEME VE RAPORLAMA ---
START_TIME=$SECONDS
while [ $((SECONDS - START_TIME)) -lt 20400 ]; do 
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Miysoft'a rapor gönder
    curl -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"Worker_$WORKER_ID\", \"cpu\":\"$CPU\", \"ram\":\"$RAM\", \"ssh\":\"$SSH_URL\", \"status\":\"RUNNING\"}" \
         https://miysoft.com/api.php
    
    sleep 30
done

# --- 7. YEDEKLEME VE DİĞER REPOYU TETİKLEME ---
pkill $NODE_NAME
rclone mkdir gdrive:avail_backup || echo "Klasör zaten var"
rclone copy identity.json gdrive:avail_backup/ --overwrite

TARGET_REPO=$([ "$GITHUB_REPOSITORY" == "Alkan789/MaxNode" ] && echo "Alkan789/MadNode" || echo "Alkan789/MaxNode")
curl -X POST -H "Authorization: token $PAT_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/$TARGET_REPO/dispatches \
     -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$((WORKER_ID + 1))\"}}"
