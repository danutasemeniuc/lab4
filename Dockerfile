FROM jenkins/ssh-agent

# Instalare PHP și tool-uri necesare
RUN apt-get update && apt-get install -y \
    php-cli \
    php-mbstring \
    php-xml \
    unzip \
    git \
    curl

# Instalare Composer
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin --filename=composer

# Verificare instalare
RUN composer --version