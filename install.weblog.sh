#!/bin/bash

# ==============================================================================
# Sunucu Log Yöneticisi - Otomatik Dağıtım Scripti v5 (Hard-coded Git URL)
# Açıklama: Proje dosyalarını GitHub'dan çeker, Nginx, Node.js, PM2,
#           Certbot ve UFW'yi kurar. API URL'lerini otomatik günceller.
#           'serviceAccountKey.json' dosyasını yerelde arar.
# Desteklenen OS: Ubuntu 22.04 / 20.04
# ==============================================================================

# Renkler
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- AYARLANACAK DEĞİŞKEN ---
# KULLANMADAN ÖNCE: Bu satırı kendi GitHub repository URL'niz ile değiştirin.
REPO_URL="https://github.com/cagrisaltik/web-log.git"
# --- ---

# Scriptin root olarak çalıştırıldığını kontrol et
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Hata: Bu script root olarak çalıştırılmalıdır (sudo ./install.sh).${NC}"
  exit 1
fi

echo -e "${GREEN}--- Sunucu Log Yöneticisi Dağıtımı Başlatılıyor ---${NC}"
echo -e "Repo klonlanacak: ${YELLOW}$REPO_URL${NC}"

# --- Değişkenleri Kullanıcıdan Al ---
# REPO_URL sorma satırı kaldırıldı.

echo -e "\n${YELLOW}Lütfen alan adı bilgilerinizi girin (Örn: alanadı.com):${NC}"
read -p "Frontend Alan Adı (tarayıcıdan erişilecek): " FRONTEND_DOMAIN

echo -e "\n${YELLOW}Lütfen backend alan adınızı girin (Örn: backend.alanadı.com):${NC}"
read -p "Backend Alan Adı (API Erişimi): " BACKEND_DOMAIN

echo -e "\n${YELLOW}Lütfen SSL sertifikası için bir e-posta adresi girin:${NC}"
read -p "Let's Encrypt E-posta Adresi: " EMAIL_FOR_SSL

# --- Adım 1: Gerekli Paketlerin Kurulumu ---
echo -e "\n${GREEN}Adım 1/9: Sistem paketleri güncelleniyor ve bağımlılıklar kuruluyor...${NC}"
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx ufw ntpdate git

echo -e "\n${GREEN}Node.js v22 (LTS) kuruluyor...${NC}"

apt-get remove -y nodejs npm
rm -rf /etc/apt/sources.list.d/nodesource.list

curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list

sudo apt-get update
sudo apt-get install -y nodejs
npm install -g npm@latest

echo "Node.js $(node -v) ve npm $(npm -v) kuruldu."

# --- Adım 2: Saati Senkronize Et (Kritik) ---
echo -e "\n${GREEN}Adım 2/9: Sunucu saati senkronize ediliyor...${NC}"
ntpdate tr.pool.ntp.org


# --- Adım 4: Proje Dizinlerini Oluşturma ve Klonlama ---
echo -e "\n${GREEN}Adım 3/9: Proje dizinleri oluşturuluyor ve repo klonlanıyor...${NC}"
PROJECT_DIR="/var/www/log-monitor"
FRONTEND="/var/www/html"
rm -rf $PROJECT_DIR # Eski kurulum varsa temizle
git clone $REPO_URL $PROJECT_DIR
if [ $? -ne 0 ]; then
    echo -e "${RED}Hata: GitHub repository klonlanamadı. URL'yi kontrol edin.${NC}"
    exit 1
fi

# Dosya yollarını belirle (Repo yapınıza göre burayı düzenleyebilirsiniz)
BACKEND_DIR="$PROJECT_DIR"
FRONTEND_DIR="$FRONTEND"
mkdir -p $FRONTEND_DIR

echo "Dizinler oluşturuldu ve proje klonlandı."

# --- Adım 5: Frontend Dosyasını Taşıma ve Güncelleme ---
echo -e "\n${GREEN}Adım 4/9: Frontend dosyası taşınıyor ve API URL'leri ayarlanıyor...${NC}"
FRONTEND_FILE_SOURCE="$PROJECT_DIR/index.html"
FRONTEND_FILE_DEST="$FRONTEND_DIR/index.html"

echo -e "\n${GREEN} Default Nginx Dosyası Aranıyor...${NC}"
 (cd $FRONTEND_DIR
TARGET="index.nginx-debian.html"

if [ -f "$TARGET" ]; then
    echo "Default Nginx HTML bulundu, dosya siliniyor..."
    rm "$TARGET"
fi 
 )

if [ ! -f "$FRONTEND_FILE_SOURCE" ]; then
    echo -e "${RED}Hata: 'index.html' dosyası klonlanan reponun ana dizininde bulunamadı.${NC}"
    exit 1
fi

cp "$FRONTEND_FILE_SOURCE" "$FRONTEND_FILE_DEST"

# API URL'lerini otomatik değiştir (sed komutu)
echo "API URL'leri güncelleniyor: https://$BACKEND_DOMAIN"
# (Buradaki 'https://backend.mhtest.info.tr' adresini reponuzdaki varsayılan adresle değiştirin)
sed -i -E "s|https://backend\.[a-zA-Z0-9.-]*|https://$BACKEND_DOMAIN|g" $FRONTEND_FILE_DEST
sed -i -E "s|wss://backend\.[a-zA-Z0-9.-]*|wss://$BACKEND_DOMAIN|g" $FRONTEND_FILE_DEST


echo "Frontend dosyası ayarlandı."

# --- Adım 6: serviceAccountKey.json (Otomatik/Manuel) ---
echo -e "\n${GREEN}Adım 5/9: 'serviceAccountKey.json' dosyası aranıyor...${NC}"
SCRIPT_RUN_DIR=$PWD
LOCAL_KEY_FILE="$SCRIPT_RUN_DIR/serviceAccountKey.json"
DEST_KEY_FILE="$BACKEND_DIR/serviceAccountKey.json"

if [ -f "$LOCAL_KEY_FILE" ]; then
    echo -e "${GREEN}'serviceAccountKey.json' yerel olarak (script dizininde) bulundu.${NC} Otomatik olarak $BACKEND_DIR dizinine kopyalanıyor..."
    cp "$LOCAL_KEY_FILE" "$DEST_KEY_FILE"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Hata: Dosya kopyalanamadı. Lütfen izinleri kontrol edin.${NC}"
        exit 1
    fi
    chown root:root "$DEST_KEY_FILE"
    chmod 600 "$DEST_KEY_FILE"
else
    echo -e "\n${YELLOW}--- KULLANICI EYLEMİ GEREKLİ (GÜVENLİK) ---${NC}"
    echo -e "${YELLOW}'serviceAccountKey.json' dosyası script dizininde bulunamadı.${NC}"
    echo "Lütfen SFTP/SCP kullanarak bu dosyayı şu dizine yükleyin:"
    echo -e "${YELLOW}$BACKEND_DIR${NC}"
    echo -e "${YELLOW}Dosyayı yükledikten sonra devam etmek için ENTER'a basın...${NC}"
    read -p ""
fi

# Son kontrol
if [ ! -f "$DEST_KEY_FILE" ]; then
    echo -e "${RED}Hata: 'serviceAccountKey.json' dosyası $BACKEND_DIR dizininde bulunamadı. Kurulum iptal ediliyor.${NC}"
    exit 1
fi

# --- Adım 7: Backend Bağımlılıklarını Yükleme ---
echo -e "\n${GREEN}Adım 6/9: Backend (Node.js) bağımlılıkları yükleniyor...${NC}"
if [ ! -f "$BACKEND_DIR/package.json" ]; then
    echo -e "${RED}Hata: 'package.json' dosyası $BACKEND_DIR dizininde bulunamadı.${NC}"
    exit 1
fi
cd $BACKEND_DIR
npm install --production
echo "Backend bağımlılıkları yüklendi."

# --- Adım 8: Nginx Yapılandırması ---
echo -e "\n${GREEN}Adım 7/9: Nginx yapılandırılıyor...${NC}"
CONFIG_FILE="/etc/nginx/sites-available/log-monitor"

cat << EOF > $CONFIG_FILE
# Frontend Web Sunucusu
server {
    listen 80;
    server_name $FRONTEND_DOMAIN;
    root $FRONTEND_DIR;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}

# Backend Reverse Proxy
server {
    listen 80;
    server_name $BACKEND_DOMAIN;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        
        # CORS Başlıkları (Certbot öncesi)
        add_header 'Access-Control-Allow-Origin' 'https://$FRONTEND_DOMAIN' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'Content-Type' always;
        
        if (\$request_method = 'OPTIONS') {
            return 204;
        }
    }
}
EOF

ln -sfn $CONFIG_FILE /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
echo "Nginx yapılandırması tamamlandı."

# --- Adım 9: SSL (Let's Encrypt) Kurulumu ---
echo -e "\n${GREEN}Adım 8/9: SSL sertifikaları alınıyor (Let's Encrypt)...${NC}"
certbot --nginx --redirect \
    -d $FRONTEND_DOMAIN \
    -d $BACKEND_DOMAIN \
    -m $EMAIL_FOR_SSL \
    --agree-tos --no-eff-email -n

systemctl restart nginx
echo "SSL başarıyla yapılandırıldı ve Nginx yeniden başlatıldı."

# --- Adım 10: Güvenlik Duvarı ve Uygulamayı Başlatma ---
echo -e "\n${GREEN}Adım 9/9: Güvenlik duvarı (UFW) ayarlanıyor ve backend başlatılıyor...${NC}"
ufw allow 'OpenSSH'
ufw allow 'Nginx Full'
ufw --force enable

echo "Backend uygulaması Screen ile başlatılıyor..."
cd $BACKEND_DIR
if [ ! -f "server.js" ]; then # Varsayım: Ana dosyanızın adı 'test.js'
    echo -e "${RED}Hata: 'server.js' dosyası $BACKEND_DIR içinde bulunamadı.${NC}"
    exit 1
fi
screen -S backend -dm bash -c "node server.js"
echo "Screen oluşturulup, Backend screen altında çalıştırıldı.."

# --- BİTİŞ ---
echo -e "\n${GREEN}--- KURULUM TAMAMLANDI!  ---${NC}"
echo -e "Frontend'e şu adresten erişebilirsiniz: ${YELLOW}https:// $FRONTEND_DOMAIN ${NC}"
echo -e "Backend API şu adreste çalışıyor: ${YELLOW}https:// $BACKEND_DOMAIN ${NC}"
echo -e "Uygulama durumunu ${YELLOW}screen -ls ${NC} komutuyla kontrol edebilirsiniz."

