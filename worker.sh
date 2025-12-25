#!/bin/bash

# --- 1. GİZLİLİK VE İSİM MASKELEME ---
# Node ismini sistem servisi gibi gösteriyoruz
NODE_FAKE_NAME="sys-update-service"
export WORKER_ID=${WORKER_ID:-1}

# --- 2. RCLONE YAPILANDIRMASI ---
mkdir -p ~/.config/rclone
echo "[gdrive]
type = drive
token = $RCLONE_TOKEN_BODY" > ~/.config/rclone/rclone.conf

# --- 3. VERİ KONTROLÜ (İLK KURULUM MU? YEDEK Mİ?) ---
echo "Google Drive kontrol ediliyor..."
if rclone ls gdrive:node_backup/snapshot.tar.zst; then
    echo "Yedek bulundu! İndiriliyor..."
    rclone copy gdrive:node_backup/snapshot.tar.zst . --progress
    tar -xf snapshot.tar.zst
    echo "Yedek başarıyla açıldı."
else
    echo "Yedek bulunamadı. Sıfırdan kurulum yapılıyor..."
    # BURAYA NODE KURULUM KOMUTLARINI EKLE (Örnek: binary indir)
    mkdir -p node_data
    # wget https://node-linki.com/binary && chmod +x binary
fi

# --- 4. NODE'U BAŞLAT (MASKELEYEREK) ---
# 'exec -a' komutu işlemin adını listede değiştirir
echo "Node başlatılıyor: $NODE_FAKE_NAME"
# ÖRNEK ÇALIŞTIRMA (Kendi binary ismine göre güncelle):
# exec -a $NODE_FAKE_NAME ./node_binary --data-dir ./node_data &
sleep 5 # Başlaması için kısa bir süre tanı

# --- 5. İZLEME VE RAPORLAMA DÖNGÜSÜ ---
START_TIME=$SECONDS
while [ $((SECONDS - START_TIME)) -lt 20400 ]; do # 5 saat 40 dakika
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Miysoft Paneline Veri Gönder (Secret'tan gelen key ile)
    curl -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"Worker_$WORKER_ID\", \"cpu\":\"$CPU\", \"ram\":\"$RAM\", \"status\":\"RUNNING\", \"time\":$(date +%s)}" \
         https://miysoft.com/api.php
    
    sleep 30
done

# --- 6. KAPANIŞ, YEDEKLEME VE EL SIKIŞMA ---
echo "Süre doluyor. Bayrak devrediliyor..."
# Node'u durdur (Eğer gerekliyse)
# pkill -f $NODE_FAKE_NAME

# Veriyi sıkıştır ve Google Drive'a gönder
tar -cf snapshot.tar.zst node_data/ 
rclone copy snapshot.tar.zst gdrive:node_backup/ --overwrite

# SIRADAKİ REPOYU TETİKLE
# Eğer MaxNode'daysan MadNode'u, MadNode'daysan MaxNode'u tetikleyecek
if [ "$GITHUB_REPOSITORY" == "Alkan789/MaxNode" ]; then
    TARGET_REPO="Alkan789/MadNode"
else
    TARGET_REPO="Alkan789/MaxNode"
fi

echo "Tetikleniyor: $TARGET_REPO"
curl -X POST -H "Authorization: token $PAT_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/$TARGET_REPO/dispatches \
     -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$((WORKER_ID + 1))\"}}"

echo "Görev tamamlandı."
