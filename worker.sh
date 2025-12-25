#!/bin/bash

# 1. Rclone Konfigürasyonunu Oluştur (Drive Bağlantısı)
mkdir -p ~/.config/rclone
echo "[gdrive]
type = drive
token = '$RCLONE_TOKEN_BODY'
team_drive = " > ~/.config/rclone/rclone.conf

# 2. Google Drive'dan Son Snapshot'ı Çek
rclone copy gdrive:node_backup/snapshot.tar.zst . --progress || echo "İlk kurulum başlıyor..."

# 3. Node'u "Gizli" İsimle Başlat
# (Burada node yazılımını indirme ve çalıştırma komutların olacak)
# Örnek: ./node_binary --name "Miysoft_Worker" & 
echo "Node başlatıldı (Maskelenmiş)..."

# 4. İzleme Döngüsü (Miysoft'a veri gönderir)
start_time=$SECONDS
while [ $((SECONDS - start_time)) -lt 20400 ]; do # 5 saat 40 dakika çalış
    cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    ram=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Miysoft API'ye Rapor Gönder
    curl -X POST -H "X-Miysoft-Key: Miysoft_Secret_123" \
         -d "{\"worker_id\":\"$WORKER_ID\", \"cpu\":\"$cpu\", \"ram\":\"$ram\", \"status\":\"RUNNING\"}" \
         https://miysoft.com/api.php
    
    sleep 30
done

# 5. Kapanış ve Yeni Action'ı Tetikleme
echo "Süre doldu, yedek alınıyor..."
# Node'u durdur, sıkıştır ve yükle
rclone copy snapshot.tar.zst gdrive:node_backup/ --overwrite

# Yeni İşçiyi Uyandır (API ile)
NEXT_WORKER=$(( (WORKER_ID % 9) + 1 ))
curl -X POST -H "Authorization: token $PAT_TOKEN" \
     -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$NEXT_WORKER\"}}" \
     https://api.github.com/repos/KULLANICI_ADIN/REPO_ADIN/dispatches
