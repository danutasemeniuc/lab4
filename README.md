# Raport Laborator 04 - Configurarea Jenkins pentru Automatizarea DevOps

## Descrierea Proiectului

Acest laborator își propune implementarea unui sistem complet de Continuous Integration și Continuous Deployment (CI/CD) utilizând Jenkins. Proiectul demonstrează configurarea unei infrastructuri Jenkins distribuite, constând dintr-un controller principal și un agent SSH, folosind Docker Compose pentru orchestrarea containerelor.

**Obiectivele principale:**
- Configurarea unui Jenkins Controller containerizat
- Implementarea unui SSH Agent cu suport pentru PHP
- Crearea unui pipeline automatizat pentru testarea proiectelor PHP
- Înțelegerea conceptelor de CI/CD în practică

**Tehnologii utilizate:**
- Docker & Docker Compose pentru containerizare
- Jenkins LTS pentru automatizare
- SSH pentru comunicarea sigură între controller și agent
- PHP & PHPUnit pentru testarea aplicațiilor

## Configurarea Jenkins Controller

### Pasul 1: Structura Inițială

Am creat structura de directoare pentru proiect:

```bash
mkdir lab4
cd lab4
mkdir secrets
```

### Pasul 2: Configurarea docker-compose.yml

Am definit serviciul Jenkins Controller cu următoarele caracteristici:

```yaml
services:
  jenkins-controller:
    image: jenkins/jenkins:lts
    container_name: jenkins-controller
    ports:
      - "8080:8080"    # Interfață web
      - "50000:50000"  # Port pentru comunicarea cu agenții
    volumes:
      - jenkins_home:/var/jenkins_home  # Persistența datelor
    networks:
      - jenkins-network
```

**Explicații:**
- **Port 8080**: Permite accesarea interfeței web Jenkins
- **Port 50000**: Utilizat pentru comunicarea JNLP cu agenții Jenkins
- **Volume jenkins_home**: Păstrează configurația și datele Jenkins între restartări
- **Network jenkins-network**: Permite comunicarea izolată între containere

### Pasul 3: Pornirea și Configurarea Inițială

```bash
docker-compose up -d
docker exec jenkins-controller cat /var/jenkins_home/secrets/initialAdminPassword
```

Am accesat `http://localhost:8080` și am urmat pașii:
1. Am introdus parola administratorului obținută din comandă
2. Am selectat "Install suggested plugins" pentru instalarea plugin-urilor esențiale
3. Am creat contul de administrator cu credențiale securizate
4. Am confirmat URL-ul Jenkins (http://localhost:8080/)

**Plugin-uri instalate automat:**
- Git plugin - pentru integrarea cu repository-uri Git
- Pipeline plugin - pentru crearea pipeline-urilor
- SSH Build Agents plugin - pentru gestionarea agenților SSH
- Credentials plugin - pentru managementul securizat al credențialelor

## Configurarea SSH Agent

### Pasul 1: Generarea Cheilor SSH

Am generat o pereche de chei SSH pentru autentificarea sigură:

```bash
cd secrets
ssh-keygen -f jenkins_agent_ssh_key -N ""
```

Această comandă a creat:
- `jenkins_agent_ssh_key` - cheia privată (păstrată secretă)
- `jenkins_agent_ssh_key.pub` - cheia publică (distribuită agent-ului)

### Pasul 2: Crearea Dockerfile pentru Agent

Am creat un Dockerfile personalizat pentru a extinde imaginea jenkins/ssh-agent:

```dockerfile
FROM jenkins/ssh-agent

# Instalare PHP-CLI și dependențe necesare
RUN apt-get update && apt-get install -y \
    php-cli \
    php-mbstring \
    php-xml \
    unzip \
    git

# Instalare Composer pentru managementul dependențelor PHP
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin --filename=composer
```

**Motivația modificărilor:**
- PHP-CLI: necesar pentru rularea scripturilor și testelor PHP
- php-mbstring, php-xml: extensii PHP cerute de PHPUnit
- Composer: manager de pachete pentru PHP
- Git: necesar pentru clonarea repository-urilor

### Pasul 3: Configurarea Serviciului SSH Agent

Am adăugat serviciul în docker-compose.yml:

```yaml
ssh-agent:
  build:
    context: .
    dockerfile: Dockerfile
  container_name: ssh-agent
  environment:
    - JENKINS_AGENT_SSH_PUBKEY=${JENKINS_AGENT_SSH_PUBKEY}
  volumes:
    - jenkins_agent_volume:/home/jenkins/agent
  depends_on:
    - jenkins-controller
  networks:
    - jenkins-network
```

### Pasul 4: Configurarea Variabilelor de Mediu

Am creat fișierul `.env` cu cheia publică:

```bash
echo "JENKINS_AGENT_SSH_PUBKEY=$(cat secrets/jenkins_agent_ssh_key.pub)" > .env
```

### Pasul 5: Înregistrarea Credențialelor în Jenkins

**În interfața Jenkins:**
1. Manage Jenkins → Manage Credentials
2. (global) → Add Credentials
3. Configurare:
   - Kind: SSH Username with private key
   - ID: jenkins-ssh-key
   - Username: jenkins
   - Private Key: Enter directly (conținutul fișierului jenkins_agent_ssh_key)

### Pasul 6: Adăugarea Nodului Agent

1. Manage Jenkins → Manage Nodes and Clouds → New Node
2. Configurare:
   - Node name: ssh-agent1
   - Type: Permanent Agent
   - Number of executors: 1
   - Remote root directory: /home/jenkins/agent
   - Labels: php-agent
   - Usage: Use this node as much as possible
   - Launch method: Launch agents via SSH
     - Host: ssh-agent
     - Credentials: jenkins-ssh-key
     - Host Key Verification Strategy: Non verifying Verification Strategy

**Verificare conexiune:**
După salvare, nodul a apărut în lista de agenți cu statusul "Agent successfully connected and online".

## Crearea și Configurarea Pipeline-ului Jenkins

### Pasul 1: Am utilizat un proiect PHP ce reprezintă un calculator

Am utilizat un proiect PHP cu următoarea structură:
```
php-calculator-project/
│
├── src/
│   ├── Calculator.php
│   └── StringHelper.php
│
├── tests/
│   ├── CalculatorTest.php
│   └── StringHelperTest.php
│
├── .gitignore
├── composer.json
├── phpunit.xml
├── Jenkinsfile
└── README.md
```

### Pasul 2: Crearea Jenkinsfile

Am definit un pipeline cu trei stage-uri principale:

```groovy
// Declarația pipeline-ului - înseamnă că folosim sintaxa declarativă Jenkins
pipeline {
    
    // AGENT - specifică UNDE va rula pipeline-ul
    agent {
        // label: selectează un agent specific după etichetă
        // 'php-agent' este numele pe care l-am dat nodului SSH agent
        // Toate task-urile vor rula pe acest agent, nu pe controller
        label 'php-agent'
    }
    
    // STAGES - conține toate etapele (stage-urile) pipeline-ului
    // Fiecare stage reprezintă o fază distinctă în procesul CI/CD
    stages {        
        
        // STAGE 1: Checkout - Obținerea codului sursă
        stage('Checkout') {
            // steps: pașii concreți care se execută în acest stage
            steps {
                // echo: afișează un mesaj în console (pentru debugging/logging)
                echo '📥 Clonare cod sursă din repository...'
                
                // checkout scm: comandă Jenkins specială
                // SCM = Source Code Management (Git, SVN, etc.)
                // Clonează codul din repository-ul configurat în job
                // Folosește automat URL-ul și branch-ul din configurația job-ului
                checkout scm
            }
        }
        
        // STAGE 2: Install Dependencies - Instalarea dependențelor
        stage('Install Dependencies') {
            steps {
                echo '📦 Instalare dependențe Composer...'
                
                // sh: execută o comandă shell în agentul Linux
                // composer install: instalează toate pachetele din composer.json
                // --no-interaction: nu solicită input de la utilizator (rulează automat)
                // --prefer-dist: descarcă arhive în loc să cloneze repository-uri (mai rapid)
                // --optimize-autoloader: optimizează autoloader-ul pentru performanță
                sh 'composer install --no-interaction --prefer-dist --optimize-autoloader'
            }
        }
        
        // STAGE 3: Code Analysis - Analiza codului
        stage('Code Analysis') {
            steps {
                echo '🔍 Verificare sintaxă PHP...'
                
                // Comandă complexă de verificare sintaxă:
                // find src tests: caută în folderele src și tests
                // -name "*.php": doar fișiere care se termină în .php
                // -exec php -l {} \;: pentru fiecare fișier găsit, execută php -l (lint check)
                // php -l: verifică sintaxa PHP fără să execute codul
                // {}: placeholder pentru numele fișierului găsit
                // \\;: termină comanda -exec (double backslash pentru escape în Groovy)
                sh 'find src tests -name "*.php" -exec php -l {} \\;'
            }
        }
        
        // STAGE 4: Run Tests - Rularea testelor
        stage('Run Tests') {
            steps {
                echo '🧪 Rulare teste PHPUnit...'
                
                // Execută testele PHPUnit:
                // ./vendor/bin/phpunit: calea către executabilul PHPUnit instalat de Composer
                // --testdox: afișează rezultatele într-un format lizibil (human-readable)
                // --colors=never: dezactivează culorile (pentru log-uri Jenkins mai curate)
                sh './vendor/bin/phpunit --testdox --colors=never'
            }
        }
    }
    
    // POST - acțiuni care se execută DUPĂ toate stage-urile
    // Se execută indiferent de rezultatul pipeline-ului
    post {
        
        // always: se execută ÎNTOTDEAUNA, indiferent de succes sau eșec
        always {
            echo '🧹 Curățare workspace...'
            
            // cleanWs(): funcție Jenkins care șterge workspace-ul
            // Eliberează spațiu pe disc
            // Previne conflicte între build-uri
            // Asigură că fiecare build pornește cu un workspace curat
            cleanWs()
        }
        
        // success: se execută DOAR dacă toate stage-urile au reușit
        success {
            echo '✅ Pipeline executat cu succes! Toate testele au trecut.'
            
            // Aici poți adăuga:
            // - Trimitere notificări (Slack, Email)
            // - Deploy automat în staging
            // - Creare artefacte
        }
        
        // failure: se execută DOAR dacă vreun stage a eșuat
        failure {
            echo '❌ Pipeline eșuat! Verifică log-urile pentru detalii.'
            
            // Aici poți adăuga:
            // - Trimitere notificări de eroare
            // - Logging extins
            // - Rollback automat
        }
    }
}
```


### Pasul 3: Configurarea Job-ului în Jenkins

1. **Crearea Job-ului:**
   - New Item → Numele: "PHP-Project-Pipeline"
   - Tip: Pipeline
   - OK

2. **Configurarea Pipeline-ului:**
   - Definition: Pipeline script from SCM
   - SCM: Git
   - Repository URL: `https://github.com/username/php-project.git`
   - Branch Specifier: */main
   - Script Path: Jenkinsfile

3. **Primul Build:**
   - Click pe "Build Now"
   - Monitorizare în "Build History"
   - Vizualizare log-uri în "Console Output"

### Pasul 4: Rezultatul Execuției

Pipeline-ul s-a executat cu succes, parcurgând toate cele trei stage-uri:

```
Started by user Admin
Running on ssh-agent1 in /home/jenkins/agent/workspace/PHP-Project-Pipeline
[Pipeline] stage (Checkout)
✓ Code checked out successfully

[Pipeline] stage (Install Dependencies)
Loading composer repositories with package information
Installing dependencies from lock file
✓ Dependencies installed

[Pipeline] stage (Test)
PHPUnit 9.5.10 by Sebastian Bergmann
✓ Calculator add functionality works correctly
✓ Calculator subtract functionality works correctly

Time: 00:00.123, Memory: 6.00 MB
OK (2 tests, 2 assertions)

[Pipeline] Post stage
✓ All stages completed successfully!
Pipeline execution completed.
```

## Răspunsuri la Întrebări

### 1. Care sunt avantajele utilizării Jenkins pentru automatizarea task-urilor DevOps?

**Automatizare completă:**
- Elimină taskurile manuale repetitive (build, test, deploy)
- Reduce eroarea umană prin standardizarea proceselor
- Accelerează timpul de livrare a software-ului

**Integrare extensivă:**
- Peste 1800 de plugin-uri disponibile
- Suport pentru diverse limbaje (Java, Python, PHP, Node.js, etc.)
- Integrare cu Git, Docker, Kubernetes, AWS, Azure, etc.

**Feedback rapid:**
- Detectarea problemelor imediat după commit
- Notificări automate prin email, Slack, sau alte canale
- Rapoarte detaliate despre build-uri și teste

**Scalabilitate:**
- Arhitectură master-slave permite distribuirea workload-ului
- Poate gestiona sute de proiecte simultan
- Suportă infrastructuri cloud și on-premise

**Open Source și Comunitate:**
- Gratuit și open-source
- Comunitate mare și activă
- Documentație extinsă și resurse de învățare

**Vizibilitate și Trasabilitate:**
- Istoric complet al build-urilor
- Posibilitatea de a reproduce orice build anterior
- Auditare completă a schimbărilor

### 2. Ce alte tipuri de agenți Jenkins există?

**1. JNLP Agent (Java Web Start Agent):**
- Agent-ul se conectează la master prin protocolul JNLP
- Util pentru machine-uri aflate în spatele firewall-urilor
- Nu necesită configurare SSH
- Exemplu de utilizare: workstation-uri Windows din rețele corporate

**2. Permanent Agent (Static Agent):**
- Agent dedicat permanent conectat la controller
- Poate fi lansat prin SSH, JNLP sau alte metode
- Cel mai stabil și previzibil
- Utilizat în laborator (ssh-agent1)

**3. Cloud Agent (Dynamic Agent):**
- Agenți creați on-demand și distruși după utilizare
- Optimizează costurile și resursele
- **Tipuri:**
  - **Docker Agent**: containere Docker create dinamic
  - **Kubernetes Agent**: pod-uri Kubernetes
  - **EC2 Agent**: instanțe AWS create automat
  - **Azure Agent**: VM-uri Azure
  - **Google Cloud Agent**: instanțe GCP

**4. Docker Agent:**
- Fiecare build rulează într-un container Docker fresh
- Izolare completă între build-uri
- Configurare prin Jenkinsfile:
```groovy
agent {
    docker {
        image 'php:8.1-cli'
    }
}
```

**5. Kubernetes Agent:**
- Agenți efemeri care rulează ca pod-uri Kubernetes
- Scalare automată bazată pe load
- Eficient pentru micro-servicii

**6. Windows Agent:**
- Agent specific pentru build-uri pe Windows
- Suportă PowerShell, MSBuild, .NET
- Conectare prin SSH sau DCOM

**7. macOS Agent:**
- Agent pentru build-uri iOS/macOS
- Necesar pentru aplicații Apple
- Suportă Xcode, Swift, Objective-C

**Comparație:**

| Tip Agent | Avantaje | Dezavantaje | Caz de utilizare |
|-----------|----------|-------------|------------------|
| SSH | Simplu, sigur | Necesită configurare manuală | Server-e dedicate |
| JNLP | Funcționează prin firewall | Mai puțin sigur | Rețele corporate |
| Docker | Izolare, reproductibilitate | Overhead containerizare | Build-uri izolate |
| Kubernetes | Auto-scaling, eficient | Complex de configurat | Infrastructuri cloud |
| Cloud (EC2/Azure) | Cost-efficient, flexibil | Latență la pornire | Load variabil |

### 3. Cu ce probleme te-ai confruntat la configurarea Jenkins și cum le-ai rezolvat?

**Problema 1: Agent-ul SSH nu se conecta la controller**

**Simptome:**
- Nodul ssh-agent1 apărea offline în Jenkins
- Mesaj de eroare: "Connection refused" sau "Host key verification failed"

**Cauze identificate:**
- Network-ul Docker nu era configurat corect
- Cheia SSH nu era încărcată corect în agent
- Host key verification bloca conexiunea

**Soluții aplicate:**
```bash
# 1. Verificat conectivitatea între containere
docker exec jenkins-controller ping ssh-agent

# 2. Verificat log-urile agent-ului
docker logs ssh-agent

# 3. Schimbat Host Key Verification Strategy în "Non verifying"
# În configurarea nodului Jenkins

# 4. Reconstruirea serviciilor pentru a încărca cheia SSH corect
docker-compose down
docker-compose up -d --build
```

**Problema 2: Composer nu era instalat în SSH Agent**

**Simptome:**
- Pipeline-ul eșua la stage-ul "Install Dependencies"
- Eroare: "composer: command not found"

**Cauză:**
- Dockerfile-ul inițial nu includea Composer
- Imaginea jenkins/ssh-agent conține doar SSH și Java

**Soluție:**
Modificat Dockerfile pentru a include Composer:
```dockerfile
FROM jenkins/ssh-agent

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
```

**Problema 3: Erori de permisiuni în workspace**

**Simptome:**
- Pipeline-ul eșua cu "Permission denied" la clonarea repository-ului
- Nu se putea scrie în /home/jenkins/agent

**Cauză:**
- Volume-ul jenkins_agent_volume avea permisiuni incorecte
- Utilizatorul jenkins din container nu avea drepturi de scriere

**Soluție:**
```bash
# Acces în containerul ssh-agent
docker exec -it ssh-agent bash

# Corectare permisiuni
chown -R jenkins:jenkins /home/jenkins/agent
chmod 755 /home/jenkins/agent

# Verificare
ls -la /home/jenkins/agent
```

**Problema 4: Plugin-ul SSH Build Agents nu era instalat**

**Simptome:**
- Opțiunea "Launch agents via SSH" nu apărea în Jenkins
- Nu se putea configura metoda de lansare SSH

**Soluție:**
1. Manage Jenkins → Manage Plugins
2. Tab "Available plugins"
3. Căutat și instalat "SSH Build Agents Plugin"
4. Restartat Jenkins: `docker-compose restart jenkins-controller`

**Problema 5: PHPUnit lipsea din proiect**

**Simptome:**
- Stage-ul de test eșua cu "phpunit: command not found"

**Soluție:**
Adăugat PHPUnit în composer.json:
```json
{
    "require-dev": {
        "phpunit/phpunit": "^9.5"
    },
    "autoload": {
        "psr-4": {
            "App\\": "src/"
        }
    }
}
```

Apoi în Jenkinsfile:
```groovy
sh 'composer install'
sh './vendor/bin/phpunit tests'
```

**Problema 6: Timeout la primul build**

**Simptome:**
- Primul build lua foarte mult timp (5-10 minute)
- Jenkins părea blocat la "Checking out code"

**Cauză:**
- Prima clonare a repository-ului este lentă
- Descărcarea dependențelor Composer pentru prima dată

**Soluție:**
- Crescut timeout-ul în configurarea nodului: 300 secunde
- Adăugat cache pentru Composer în Dockerfile:
```dockerfile
ENV COMPOSER_CACHE_DIR=/tmp/composer-cache
RUN mkdir -p /tmp/composer-cache
```

**Lecții învățate:**

1. **Importanța log-urilor**: Întotdeauna verifică log-urile containerelor pentru debugging
   ```bash
   docker logs jenkins-controller
   docker logs ssh-agent
   ```

2. **Testarea conectivității**: Verifică rețeaua între containere înainte de configurări complexe
   ```bash
   docker network inspect lab04_jenkins-network
   ```

3. **Verificarea imaginilor Docker**: Asigură-te că toate dependențele sunt instalate în Dockerfile
   ```bash
   docker exec ssh-agent which composer
   docker exec ssh-agent php --version
   ```

4. **Backup configurației**: Exportă configurația Jenkins periodic
   ```bash
   docker exec jenkins-controller tar czf /tmp/jenkins-backup.tar.gz /var/jenkins_home
   docker cp jenkins-controller:/tmp/jenkins-backup.tar.gz ./backup/
   ```

## Concluzii

Acest laborator a demonstrat implementarea cu succes a unui sistem CI/CD complet folosind Jenkins. Am învățat:

1. **Containerizare**: Folosirea Docker Compose pentru orchestrarea infrastructurii
2. **Securitate**: Implementarea autentificării SSH între componente
3. **Automatizare**: Crearea pipeline-urilor declarative pentru testare automată
4. **Scalabilitate**: Arhitectura master-agent permite extinderea ușoară

**Aplicabilitate practică:**
- Sistemul poate fi extins pentru proiecte reale de producție
- Pipeline-ul poate fi îmbunătățit cu deploy automation
- Infrastructura poate scala adăugând mai mulți agenți

**Pași următori:**
- Integrare cu GitHub Webhooks pentru build-uri automate la push
- Adăugare stage pentru deploy în medii de staging/production
- Implementare notificări prin Slack sau email
- Configurare backup automat pentru datele Jenkins

## Resurse și Referințe

- [Jenkins Official Documentation](https://www.jenkins.io/doc/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [PHPUnit Manual](https://phpunit.de/documentation.html)
- [Jenkins Pipeline Syntax](https://www.jenkins.io/doc/book/pipeline/syntax/)
- [SSH Build Agents Plugin](https://plugins.jenkins.io/ssh-slaves/)

## Anexe

### Fișiere de configurare complete

**docker-compose.yml:**
```yaml
services:
  jenkins-controller:
    image: jenkins/jenkins:lts
    container_name: jenkins-controller
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
    networks:
      - jenkins-network

  ssh-agent:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: ssh-agent
    environment:
      - JENKINS_AGENT_SSH_PUBKEY=${JENKINS_AGENT_SSH_PUBKEY}
    volumes:
      - jenkins_agent_volume:/home/jenkins/agent
    depends_on:
      - jenkins-controller
    networks:
      - jenkins-network

volumes:
  jenkins_home:
  jenkins_agent_volume:

networks:
  jenkins-network:
    driver: bridge
```

**Dockerfile:**
```dockerfile
FROM jenkins/ssh-agent

RUN apt-get update && apt-get install -y \
    php-cli \
    php-mbstring \
    php-xml \
    unzip \
    git \
    curl

RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin --filename=composer

RUN composer --version
```

**Jenkinsfile:**
```groovy
pipeline {
    agent {
        label 'php-agent'
    }
    
    stages {        
        stage('Checkout') {
            steps {
                echo 'Checking out code...'
                checkout scm
            }
        }
        
        stage('Install Dependencies') {
            steps {
                echo 'Installing dependencies...'
                sh 'composer install --no-interaction --prefer-dist'
            }
        }
        
        stage('Test') {
            steps {
                echo 'Running tests...'
                sh './vendor/bin/phpunit --testdox tests'
            }
        }
    }
    
    post {
        always {
            echo 'Pipeline completed.'
            cleanWs()
        }
        success {
            echo 'All stages completed successfully!'
        }
        failure {
            echo 'Errors detected in the pipeline.'
        }
    }
}
```
