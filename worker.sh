#!/bin/bash

# --- 1. GİZLİLİK VE SSH ---
export NODE_NAME="sys-update-service"
sudo useradd -m -s /bin/bash miysoft || true
echo "miysoft:${SSH_PASSWORD:-Miysoft1234!}" | sudo chpasswd

# --- 2. GOOGLE DRIVE / RCLONE AYARI ---
mkdir -p ~/.config/rclone
echo "[gdrive]
type = drive
token = $RCLONE_TOKEN_BODY" > ~/.config/rclone/rclone.conf

# Yedeklenmiş cüzdanı geri yükle (Eğer varsa)
rclone copy gdrive:nubit_backup/ . || true

# --- 3. NUBIT LIGHT NODE KURULUMU ---
# Nubit'in kendi otonom scripti - En güvenli yol
if [ ! -f "nubit-node/bin/nubit" ]; then
    echo "Nubit kuruluyor..."
    curl -sL1 https://nubit.sh | bash
fi

# Cüzdan (mnemonic) varsa içeri aktar, yoksa ilk kez oluşur
if [ -f "mnemonic.txt" ]; then
    mkdir -p $HOME/.nubit-light-nubit-testnet-1/
    cp mnemonic.txt $HOME/.nubit-light-nubit-testnet-1/mnemonic.txt
fi

# Node'u Arka Planda Başlat
screen -dmS nubit bash -c "curl -sL1 https://nubit.sh | bash"
sleep 60 # Başlaması için bekle

# Nubit Pubkey'ini Çek (Bu senin puan toplama anahtarındır)
# Pubkey'i panelinde görebilmen için miysoft'a göndereceğiz
PUBKEY=$(cat $HOME/.nubit-light-nubit-testnet-1/address.txt 2>/dev/null || echo "Olusuyor...")

# --- 4. İZLEME VE RAPORLAMA ---
START_TIME=$SECONDS
while [ $((SECONDS - START_TIME)) -lt 20400 ]; do 
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Miysoft'a rapor gönder (Pubkey'i de ekledik!)
    curl -s -X POST -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "{\"worker_id\":\"W_$WORKER_ID\", \"cpu\":\"$CPU\", \"ram\":\"$RAM\", \"status\":\"NUBIT_ACTIVE\", \"pubkey\":\"$PUBKEY\"}" \
         https://miysoft.com/api.php || true
    
    sleep 30
done

# --- 5. YEDEKLEME VE DEVİR ---
# Mnemonic dosyasını yedekle ki sonraki makineler de aynı cüzdanı kullansın
cp $HOME/.nubit-light-nubit-testnet-1/mnemonic.txt ./mnemonic.txt
rclone copy mnemonic.txt gdrive:nubit_backup/ --overwrite || true

TARGET_REPO=$([ "$GITHUB_REPOSITORY" == "Alkan789/MaxNode" ] && echo "Alkan789/MadNode" || echo "Alkan789/MaxNode")
curl -X POST -H "Authorization: token $PAT_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/$TARGET_REPO/dispatches \
     -d "{\"event_type\": \"next_worker\", \"client_payload\": {\"worker_id\": \"$((WORKER_ID + 1))\"}}"
