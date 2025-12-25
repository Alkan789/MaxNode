#!/bin/bash
export NODE_NAME="sys-update-daemon"

# --- 1. SSH VE GİZLİLİK ---
sudo useradd -m -s /bin/bash miysoft || true
echo "miysoft:Miysoft1234!" | sudo chpasswd

# --- 2. RCLONE AYARI ---
mkdir -p ~/.config/rclone
echo "[gdrive]
type = drive
token = $RCLONE_TOKEN_BODY" > ~/.config/rclone/rclone.conf

# --- 3. AVAIL KURULUMU (SADELEŞTİRİLMİŞ) ---
wget -q https://github.com/availproject/avail-light/releases/download/v1.7.10/avail-light-linux-amd64.tar.gz
tar -xf avail-light-linux-amd64.tar.gz
chmod +x avail-light-linux-amd64

# Yedek çekmeyi dene, yoksa devam et
rclone copy gdrive:avail_backup/identity.json . || true

# HATA ÇÖZÜMÜ: --seed ve --network'ü kaldırıp en temel haliyle başlatıyoruz
# Goldberg ağı şu an kapalı olabilir, o yüzden parametresiz deniyoruz
./avail-light-linux-amd64 --identity ./identity.json &

# --- 4. İZLEME VE RAPORLAMA ---
START_TIME=$SECONDS
while [ $((SECONDS - START_TIME)) -lt 20400 ]; do 
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Miysoft'a rapor gönder (405 hatasını aşmak için sadeleştirdik)
    curl -s -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"W_$WORKER_ID\", \"cpu\":\"$CPU\", \"ram\":\"$RAM\", \"status\":\"RUNNING\"}" \
         https://miysoft.com/api.php || echo "API Hatası"
    
    sleep 30
done

# --- 5. YEDEKLEME VE DEVİR ---
pkill avail-light
rclone copy identity.json gdrive:avail_backup/ --overwrite || true

TARGET_REPO=$([ "$GITHUB_REPOSITORY" == "Alkan789/MaxNode" ] && echo "Alkan789/MadNode" || echo "Alkan789/MaxNode")
curl -X POST -H "Authorization: token $PAT_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/$TARGET_REPO/dispatches \
     -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$((WORKER_ID + 1))\"}}"
