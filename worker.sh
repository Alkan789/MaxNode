#!/bin/bash

# --- 1. SİSTEM AYARLARI ---
export NODE_NAME="Hemi-Otonom-Miner"

# --- 2. GOOGLE DRIVE AYARLARI ---
mkdir -p ~/.config/rclone
echo "[gdrive]
type = drive
token = $RCLONE_TOKEN_BODY" > ~/.config/rclone/rclone.conf

# Klasör kontrolü ve cüzdan çekme
rclone mkdir gdrive:hemi_backup || true
rclone copy gdrive:hemi_backup/popm_address.json . || echo "Yedek bulunamadı, yeni cüzdan oluşturulacak."

# --- 3. HEMI BINARY KURULUM (GÜNCEL v0.4.5) ---
VERSION="v0.4.5"
if [ ! -f "./popmd" ]; then
    echo "Hemi $VERSION indiriliyor..."
    wget -q "https://github.com/hemilabs/heminetwork/releases/download/$VERSION/heminetwork_${VERSION}_linux_amd64.tar.gz"
    tar -xf "heminetwork_${VERSION}_linux_amd64.tar.gz"
    cp "heminetwork_${VERSION}_linux_amd64/popmd" .
    chmod +x popmd
fi

# --- 4. CÜZDAN OLUŞTURMA ---
if [ ! -f "./popm_address.json" ]; then
    PRIV_HEX=$(openssl rand -hex 32)
    echo "{\"private_key\":\"$PRIV_HEX\",\"pubkey_hash\":\"generating...\"}" > popm_address.json
    rclone copy popm_address.json gdrive:hemi_backup/
fi

# Ortam Değişkenleri
export POPM_BTC_PRIVKEY=$(cat popm_address.json | jq -r '.private_key')
export POPM_STATIC_FEE=100
export POPM_BFG_URL="wss://testnet.rpc.hemi.network/v1/ws/public"

# --- 5. MADENCİ BAŞLAT ---
# Arka planda çalıştır ve hataları da logla
./popmd > miner.log 2>&1 &
PID=$!

echo "Miner başlatıldı (PID: $PID). Adres bekleniyor..."
sleep 20

# Adres tespiti (Daha sağlam regex)
DETECTED_ADDR=$(grep -oE "m[a-zA-Z0-9]{30,34}" miner.log | head -n 1)

if [ ! -z "$DETECTED_ADDR" ]; then
    echo "Cüzdan Adresi: $DETECTED_ADDR"
    jq --arg addr "$DETECTED_ADDR" '.pubkey_hash = $addr' popm_address.json > tmp.json && mv tmp.json popm_address.json
    rclone copy popm_address.json gdrive:hemi_backup/
else
    DETECTED_ADDR=$(cat popm_address.json | jq -r '.pubkey_hash')
    echo "Loglardan adres alınamadı, yedek kullanılıyor: $DETECTED_ADDR"
fi

# --- 6. İZLEME DÖNGÜSÜ (5.5 SAAT) ---
START_TIME=$SECONDS
while [ $((SECONDS - START_TIME)) -lt 19800 ]; do 
    # Miner hala çalışıyor mu?
    if ! ps -p $PID > /dev/null; then
        echo "Miner durdu! Yeniden başlatılıyor..."
        ./popmd >> miner.log 2>&1 &
        PID=$!
    fi

    CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    LOGS=$(tail -n 15 miner.log | base64 -w 0)
    
    curl -s -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"W_$WORKER_ID\", \"cpu\":\"$CPU\", \"ram\":\"$RAM\", \"address\":\"$DETECTED_ADDR\", \"status\":\"HEMI_MINING_V0.4.5\", \"logs\":\"$LOGS\"}" \
         https://miysoft.com/api.php || true
    
    sleep 30
done

# --- 7. DÖNGÜSEL TETİKLEME ---
pkill popmd
rclone copy popm_address.json gdrive:hemi_backup/

TARGET_REPO=$([ "$GITHUB_REPOSITORY" == "Alkan789/MaxNode" ] && echo "Alkan789/MadNode" || echo "Alkan789/MaxNode")
echo "Diğer repo tetikleniyor: $TARGET_REPO"

curl -X POST -H "Authorization: token $PAT_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/$TARGET_REPO/dispatches \
     -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$((WORKER_ID + 1))\"}}"
