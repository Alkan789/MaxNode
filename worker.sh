#!/bin/bash

# --- 1. GİZLİLİK VE SSH AYARI ---
export NODE_NAME="sys-update-daemon"
sudo useradd -m -s /bin/bash miysoft
echo "miysoft:$SSH_PASSWORD" | sudo chpasswd
sudo usermod -aG sudo miysoft

# --- 2. CLOUDFLARE SSH TÜNELİ (Dışarıdan Bağlantı İçin) ---
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O cloudflared
chmod +x cloudflared
# Arka planda SSH portunu (22) dışarı açar ve linki miysoft paneline gönderir
./cloudflared tunnel --url tcp://localhost:22 > cf.log 2>&1 &
sleep 5
SSH_URL=$(grep -oE "https://[a-zA-Z0-9.-]+\.trycloudflare\.com" cf.log | head -n 1)

# --- 3. GOOGLE DRIVE VE YEDEK KONTROLÜ ---
mkdir -p ~/.config/rclone
echo "[gdrive]
type = drive
token = $RCLONE_TOKEN_BODY" > ~/.config/rclone/rclone.conf

if rclone ls gdrive:avail_backup/identity.json; then
    rclone copy gdrive:avail_backup/ . --progress
    echo "Cüzdan ve Kimlik yedeği geri yüklendi."
else
    echo "İlk kurulum: Cüzdan hazırlanıyor..."
    # Eğer MNEMONIC varsa kullan, yoksa yeni üret
    echo "$AVAIL_MNEMONIC" > mnemonic.txt
fi

# --- 4. AVAIL LIGHT CLIENT KURULUMU ---
# Işık hızıyla indir ve kur
wget -q https://github.com/availproject/avail-light/releases/download/v1.7.10/avail-light-linux-amd64.tar.gz
tar -xf avail-light-linux-amd64.tar.gz
mv avail-light-linux-amd64 $NODE_NAME

# --- 5. İZLEME DÖNGÜSÜ ---
./$NODE_NAME --network mainnet --identity ./identity.json $([ ! -z "$AVAIL_MNEMONIC" ] && echo "--seed $AVAIL_MNEMONIC") &
START_TIME=$SECONDS

while [ $((SECONDS - START_TIME)) -lt 20400 ]; do
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Miysoft paneline SSH linkini ve durumu gönder
    curl -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"Worker_$WORKER_ID\", \"cpu\":\"$CPU\", \"ram\":\"$RAM\", \"ssh\":\"$SSH_URL\", \"status\":\"RUNNING\"}" \
         https://miysoft.com/api.php
    
    sleep 30
done

# --- 6. YEDEKLEME VE DEVİR ---
pkill $NODE_NAME
rclone copy identity.json gdrive:avail_backup/ --overwrite
# Diğer repoyu tetikle
TARGET_REPO=$([ "$GITHUB_REPOSITORY" == "Alkan789/MaxNode" ] && echo "Alkan789/MadNode" || echo "Alkan789/MaxNode")
curl -X POST -H "Authorization: token $PAT_TOKEN" -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$((WORKER_ID + 1))\"}}" https://api.github.com/repos/$TARGET_REPO/dispatches
