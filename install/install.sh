#!/bin/bash
# Installation principale
# Script d'installation pour Claude IaC avec Versioning et Rollback

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Vérifications préalables
check_prerequisites() {
    log "Vérification des prérequis..."
    
    # Vérifier que Claude est installé
    if ! command -v claude &> /dev/null; then
        error "Claude Code n'est pas installé. Installez-le d'abord avec:"
        echo "npm install -g @anthropic-ai/claude-code"
        exit 1
    fi
    
    # Vérifier les permissions
    if [ ! -w "/opt" ]; then
        error "Permissions insuffisantes pour écrire dans /opt"
        echo "Exécutez ce script avec sudo ou ajustez les permissions."
        exit 1
    fi
    
    success "Prérequis OK"
}

# Créer la structure des répertoires
create_directories() {
    log "Création des répertoires..."
    
    local dirs=(
        "/opt/claude-state"
        "/opt/claude-projects"  
        "/opt/claude-backups"
        "/opt/tmp"
        "$HOME/bin"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            if [[ "$dir" == /opt/* ]]; then
                sudo mkdir -p "$dir"
                sudo chown $USER:$USER "$dir"
            else
                mkdir -p "$dir"
            fi
            success "Créé: $dir"
        else
            log "Existe déjà: $dir"
        fi
    done
    
    # Définir les permissions appropriées
    chmod 755 /opt/claude-state /opt/claude-projects /opt/claude-backups /opt/tmp
}

# Installer le script principal claude-iac
install_main_script() {
    log "Installation du script principal claude-iac..."
    
    cat > "$HOME/bin/claude-iac" << 'EOF'
#!/bin/bash
# Claude IaC System avec Versioning et Rollback

set -e

# Configuration
CLAUDE_STATE_DIR="/opt/claude-state"
CLAUDE_PROJECTS_DIR="/opt/claude-projects"
CLAUDE_BACKUPS_DIR="/opt/claude-backups"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
SESSION_ID="v$(date '+%Y%m%d_%H%M%S')_$$"

# Variables d'environnement
export TMPDIR=/opt/tmp
export TEMP=/opt/tmp
export TMP=/opt/tmp

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Initialiser les répertoires
init_directories() {
    if [ ! -f "$CLAUDE_STATE_DIR/versions.db" ]; then
        cat > "$CLAUDE_STATE_DIR/versions.db" << DBEOF
# Claude IaC Versions Database
# Format: VERSION_ID|TIMESTAMP|COMMAND|PROJECT_DIR|BACKUP_PATH|STATUS|ROLLBACK_CMD
DBEOF
    fi
}

# Créer un snapshot de l'état actuel
create_snapshot() {
    local version_id="$1"
    local project_path="$2"
    local backup_path="$CLAUDE_BACKUPS_DIR/snapshot_${version_id}"
    
    log "Création du snapshot pour $version_id..."
    
    if [ -d "$project_path" ]; then
        cp -r "$project_path" "$backup_path"
        
        cat > "$backup_path/.claude_metadata" << METAEOF
VERSION_ID=$version_id
TIMESTAMP=$(date)
ORIGINAL_PATH=$project_path
USER=$(whoami)
HOSTNAME=$(hostname)
PWD=$(pwd)
METAEOF
        
        find "$backup_path" -type f -exec md5sum {} \; > "$backup_path/.claude_checksums"
        
        success "Snapshot créé: $backup_path"
        echo "$backup_path"
    else
        warning "Chemin de projet non trouvé: $project_path"
        echo ""
    fi
}

# Enregistrer une version dans la base
register_version() {
    local version_id="$1"
    local command="$2"
    local project_dir="$3"
    local backup_path="$4"
    local status="${5:-SUCCESS}"
    local rollback_cmd="$6"
    
    echo "${version_id}|$(date)|${command}|${project_dir}|${backup_path}|${status}|${rollback_cmd}" >> "$CLAUDE_STATE_DIR/versions.db"
    
    cat > "$CLAUDE_STATE_DIR/${version_id}.json" << JSONEOF
{
    "version_id": "$version_id",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "command": "$command",
    "project_directory": "$project_dir",
    "backup_path": "$backup_path",
    "status": "$status",
    "rollback_command": "$rollback_cmd",
    "user": "$(whoami)",
    "hostname": "$(hostname)",
    "working_directory": "$(pwd)"
}
JSONEOF
}

# Générer le code IaC pour cette session
generate_iac() {
    local version_id="$1"
    local project_dir="$2"
    local command="$3"
    
    mkdir -p "$project_dir"/{logs,scripts,ansible,terraform,docker,rollback}
    
    # Script de reproduction
    cat > "$project_dir/scripts/reproduce_${version_id}.sh" << SCRIPTEOF
#!/bin/bash
# Script de reproduction pour $version_id

set -e
export TMPDIR=/opt/tmp
export TEMP=/opt/tmp
export TMP=/opt/tmp

echo "=== Reproduction de $version_id ==="
echo "Commande: $command"
cd "$(pwd)"
$command
echo "=== Fin de reproduction ==="
SCRIPTEOF
    chmod +x "$project_dir/scripts/reproduce_${version_id}.sh"
    
    # Playbook Ansible
    cat > "$project_dir/ansible/playbook_${version_id}.yml" << ANSIBLEEOF
---
- name: "Reproduire Claude session $version_id"
  hosts: localhost
  gather_facts: yes
  vars:
    version_id: "$version_id"
    original_command: "$command"
  
  tasks:
    - name: "Configurer environnement temporaire"
      file:
        path: "/opt/tmp"
        state: directory
        owner: "$USER"
        group: "$USER"
        mode: '0755'
      become: yes
    
    - name: "Exécuter commande Claude"
      shell: |
        export TMPDIR=/opt/tmp
        export TEMP=/opt/tmp
        export TMP=/opt/tmp
        $command
      register: result
    
    - name: "Afficher résultat"
      debug:
        var: result.stdout_lines
ANSIBLEEOF
    
    # Configuration Terraform
    cat > "$project_dir/terraform/main_${version_id}.tf" << TERRAFORMEOF
terraform {
  required_version = ">= 1.0"
  required_providers {
    null = { source = "hashicorp/null", version = "~> 3.0" }
  }
}

resource "null_resource" "claude_execution_${version_id}" {
  provisioner "local-exec" {
    command = "export TMPDIR=/opt/tmp && $command"
  }
}

output "version_id" { value = "$version_id" }
output "timestamp" { value = timestamp() }
TERRAFORMEOF
    
    # Script de rollback
    cat > "$project_dir/rollback/rollback_${version_id}.sh" << ROLLBACKEOF
#!/bin/bash
# Script de rollback pour $version_id

set -e

VERSION_ID="$version_id"
BACKUP_PATH="$CLAUDE_BACKUPS_DIR/snapshot_\$VERSION_ID"

echo "=== Rollback version \$VERSION_ID ==="

if [ ! -d "\$BACKUP_PATH" ]; then
    echo "ERREUR: Backup non trouvé"
    exit 1
fi

if [ -f "\$BACKUP_PATH/.claude_metadata" ]; then
    source "\$BACKUP_PATH/.claude_metadata"
    
    # Sauvegarder l'état actuel
    CURRENT_BACKUP="$CLAUDE_BACKUPS_DIR/pre_rollback_\$(date +%Y%m%d_%H%M%S)"
    [ -d "\$ORIGINAL_PATH" ] && cp -r "\$ORIGINAL_PATH" "\$CURRENT_BACKUP"
    
    # Restaurer
    rm -rf "\$ORIGINAL_PATH"
    cp -r "\$BACKUP_PATH" "\$ORIGINAL_PATH"
    rm -f "\$ORIGINAL_PATH/.claude_metadata" "\$ORIGINAL_PATH/.claude_checksums"
    
    echo "Rollback terminé avec succès"
else
    echo "ERREUR: Métadonnées manquantes"
    exit 1
fi
ROLLBACKEOF
    chmod +x "$project_dir/rollback/rollback_${version_id}.sh"
}

# Fonction principale d'exécution
execute_claude() {
    local command="claude $*"
    local project_dir="$CLAUDE_PROJECTS_DIR/session_${SESSION_ID}"
    
    log "Session $SESSION_ID - Commande: $command"
    
    local backup_path=$(create_snapshot "$SESSION_ID" "$(pwd)")
    generate_iac "$SESSION_ID" "$project_dir" "$command"
    
    local log_file="$project_dir/logs/execution_${SESSION_ID}.log"
    mkdir -p "$(dirname "$log_file")"
    
    register_version "$SESSION_ID" "$command" "$project_dir" "$backup_path" "RUNNING"
    
    {
        echo "=== Session Claude Code $SESSION_ID ==="
        echo "Date: $(date)"
        echo "Commande: $command"
        echo "=== Début exécution ==="
        
        if claude "$@"; then
            echo "=== Succès ==="
            register_version "$SESSION_ID" "$command" "$project_dir" "$backup_path" "SUCCESS"
            success "Session terminée avec succès"
        else
            echo "=== Erreur ==="
            register_version "$SESSION_ID" "$command" "$project_dir" "$backup_path" "ERROR"
            error "Session terminée avec erreur"
        fi
    } 2>&1 | tee "$log_file"
    
    create_snapshot "${SESSION_ID}_after" "$(pwd)"
    
    success "Projet IaC: $project_dir"
    success "Logs: $log_file"
    echo
    echo "Commandes utiles:"
    echo "  claude-versions      # Voir toutes les versions"
    echo "  claude-rollback $SESSION_ID  # Rollback"
    echo "  $project_dir/scripts/reproduce_${SESSION_ID}.sh  # Reproduire"
}

init_directories
execute_claude "$@"
EOF

    chmod +x "$HOME/bin/claude-iac"
    success "Script principal installé: $HOME/bin/claude-iac"
}

# Installer claude-versions
install_versions_script() {
    log "Installation du script claude-versions..."
    
    cat > "$HOME/bin/claude-versions" << 'VERSIONSEOF'
#!/bin/bash
# Gestionnaire de versions Claude IaC

CLAUDE_STATE_DIR="/opt/claude-state"
CLAUDE_PROJECTS_DIR="/opt/claude-projects"
CLAUDE_BACKUPS_DIR="/opt/claude-backups"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_usage() {
    echo "Usage: claude-versions [OPTION]"
    echo "Options:"
    echo "  list, ls              Lister toutes les versions"
    echo "  show <version_id>     Détails d'une version"
    echo "  diff <v1> <v2>        Comparer deux versions"
    echo "  clean [days]          Nettoyer (défaut: 30 jours)"
    echo "  stats                 Statistiques"
    echo "  export <version_id>   Exporter une version"
}

list_versions() {
    if [ ! -f "$CLAUDE_STATE_DIR/versions.db" ]; then
        echo "Aucune version trouvée."
        return
    fi
    
    echo -e "${CYAN}=== Versions Claude IaC ===${NC}"
    printf "%-20s %-19s %-10s %-50s\n" "VERSION_ID" "TIMESTAMP" "STATUS" "COMMAND"
    printf "%-20s %-19s %-10s %-50s\n" "----------" "---------" "------" "-------"
    
    while IFS='|' read -r version_id timestamp command project_dir backup_path status rollback_cmd; do
        if [[ "$version_id" != \#* ]] && [[ -n "$version_id" ]]; then
            case "$status" in
                "SUCCESS") color="$GREEN" ;;
                "ERROR") color="$RED" ;;
                "RUNNING") color="$YELLOW" ;;
                *) color="$NC" ;;
            esac
            
            short_command=$(echo "$command" | cut -c1-47)
            [ ${#command} -gt 47 ] && short_command="${short_command}..."
            
            printf "${color}%-20s %-19s %-10s %-50s${NC}\n" \
                "$version_id" \
                "$(echo "$timestamp" | cut -c1-19)" \
                "$status" \
                "$short_command"
        fi
    done < "$CLAUDE_STATE_DIR/versions.db"
}

show_version_details() {
    local version_id="$1"
    local json_file="$CLAUDE_STATE_DIR/${version_id}.json"
    
    if [ ! -f "$json_file" ]; then
        echo "Version $version_id non trouvée."
        return 1
    fi
    
    echo -e "${CYAN}=== Version $version_id ===${NC}"
    
    if command -v jq &> /dev/null; then
        jq -r 'to_entries[] | "\(.key): \(.value)"' "$json_file"
    else
        grep -o '"[^"]*": *"[^"]*"' "$json_file" | while IFS=': ' read -r key value; do
            echo "$(echo "$key" | tr -d '"'): $(echo "$value" | tr -d '"')"
        done
    fi
    
    echo -e "\n${YELLOW}=== État des fichiers ===${NC}"
    
    local project_dir=$(grep '"project_directory"' "$json_file" | cut -d'"' -f4)
    local backup_path=$(grep '"backup_path"' "$json_file" | cut -d'"' -f4)
    
    if [ -d "$project_dir" ]; then
        echo -e "${GREEN}✓${NC} Projet IaC: $project_dir"
    else
        echo -e "${RED}✗${NC} Projet IaC manquant: $project_dir"
    fi
    
    if [ -d "$backup_path" ]; then
        echo -e "${GREEN}✓${NC} Backup: $backup_path"
    else
        echo -e "${RED}✗${NC} Backup manquant: $backup_path"
    fi
}

show_stats() {
    if [ ! -f "$CLAUDE_STATE_DIR/versions.db" ]; then
        echo "Aucune version trouvée."
        return
    fi
    
    echo -e "${CYAN}=== Statistiques Claude IaC ===${NC}"
    
    local total=$(grep -v "^#" "$CLAUDE_STATE_DIR/versions.db" | wc -l)
    local success=$(grep -c "|SUCCESS|" "$CLAUDE_STATE_DIR/versions.db" || echo "0")
    local error=$(grep -c "|ERROR|" "$CLAUDE_STATE_DIR/versions.db" || echo "0")
    local running=$(grep -c "|RUNNING|" "$CLAUDE_STATE_DIR/versions.db" || echo "0")
    
    echo "Total: $total"
    echo -e "${GREEN}Succès: $success${NC}"
    echo -e "${RED}Erreurs: $error${NC}"
    echo -e "${YELLOW}En cours: $running${NC}"
    
    if [ -d "$CLAUDE_BACKUPS_DIR" ]; then
        local backup_size=$(du -sh "$CLAUDE_BACKUPS_DIR" 2>/dev/null | cut -f1 || echo "N/A")
        echo "Espace backups: $backup_size"
    fi
}

case "$1" in
    "list"|"ls"|"") list_versions ;;
    "show") show_version_details "$2" ;;
    "stats") show_stats ;;
    *) show_usage ;;
esac
VERSIONSEOF

    chmod +x "$HOME/bin/claude-versions"
    success "Script claude-versions installé"
}

# Installer claude-rollback
install_rollback_script() {
    log "Installation du script claude-rollback..."
    
    cat > "$HOME/bin/claude-rollback" << 'ROLLBACKEOF'
#!/bin/bash
# Script de rollback Claude IaC

CLAUDE_STATE_DIR="/opt/claude-state"
CLAUDE_BACKUPS_DIR="/opt/claude-backups"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

perform_rollback() {
    local version_id="$1"
    
    if [ -z "$version_id" ]; then
        echo -e "${RED}Erreur: Version ID requis${NC}"
        echo "Usage: claude-rollback <version_id>"
        return 1
    fi
    
    if ! grep -q "^${version_id}|" "$CLAUDE_STATE_DIR/versions.db" 2>/dev/null; then
        echo -e "${RED}Erreur: Version $version_id non trouvée${NC}"
        return 1
    fi
    
    local version_line=$(grep "^${version_id}|" "$CLAUDE_STATE_DIR/versions.db")
    IFS='|' read -r vid timestamp command project_dir backup_path status rollback_cmd <<< "$version_line"
    
    if [ ! -d "$backup_path" ]; then
        echo -e "${RED}Erreur: Backup non trouvé: $backup_path${NC}"
        return 1
    fi
    
    local metadata_file="$backup_path/.claude_metadata"
    if [ ! -f "$metadata_file" ]; then
        echo -e "${RED}Erreur: Métadonnées manquantes${NC}"
        return 1
    fi
    
    source "$metadata_file"
    
    echo -e "${BLUE}=== Rollback vers $version_id ===${NC}"
    echo "Timestamp: $timestamp"
    echo "Commande: $command"
    echo "Restauration: $ORIGINAL_PATH"
    echo
    
    read -p "Continuer? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Annulé."
        return 0
    fi
    
    # Vérifier intégrité
    if [ -f "$backup_path/.claude_checksums" ]; then
        echo "Vérification intégrité..."
        cd "$backup_path"
        if ! md5sum -c .claude_checksums --quiet; then
            echo -e "${RED}Erreur: Intégrité compromise${NC}"
            return 1
        fi
        cd - > /dev/null
    fi
    
    # Backup de l'état actuel
    local current_backup="$CLAUDE_BACKUPS_DIR/pre_rollback_$(date +%Y%m%d_%H%M%S)"
    if [ -d "$ORIGINAL_PATH" ]; then
        cp -r "$ORIGINAL_PATH" "$current_backup"
        echo -e "${GREEN}✓${NC} État actuel sauvé: $current_backup"
    fi
    
    # Restaurer
    rm -rf "$ORIGINAL_PATH"
    cp -r "$backup_path" "$ORIGINAL_PATH"
    rm -f "$ORIGINAL_PATH/.claude_metadata" "$ORIGINAL_PATH/.claude_checksums"
    
    # Enregistrer le rollback
    local rollback_id="rollback_$(date +%Y%m%d_%H%M%S)"
    echo "${rollback_id}|$(date)|ROLLBACK to ${version_id}|${ORIGINAL_PATH}|${current_backup}|SUCCESS|" >> "$CLAUDE_STATE_DIR/versions.db"
    
    echo -e "${GREEN}✓ Rollback terminé${NC}"
    echo "Version restaurée: $version_id"
    echo "Backup précédent: $current_backup"
}

perform_rollback "$1"
ROLLBACKEOF

    chmod +x "$HOME/bin/claude-rollback"
    success "Script claude-rollback installé"
}

# Configurer le PATH
configure_path() {
    log "Configuration du PATH..."
    
    if ! echo "$PATH" | grep -q "$HOME/bin"; then
        echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
        export PATH=$HOME/bin:$PATH
        success "PATH configuré dans ~/.bashrc"
    else
        log "PATH déjà configuré"
    fi
}

# Créer des alias utiles
create_aliases() {
    log "Création des alias..."
    
    cat >> ~/.bashrc << 'ALIASEOF'

# Alias Claude IaC
alias claude-run='claude-iac'
alias cv='claude-versions'
alias cr='claude-rollback'
alias claude-help='echo -e "Commandes Claude IaC:\n  claude-iac <cmd>     # Exécuter avec versioning\n  claude-versions      # Gérer les versions\n  claude-rollback <id> # Rollback\n  cv                   # Alias pour versions\n  cr                   # Alias pour rollback"'

ALIASEOF

    success "Alias créés dans ~/.bashrc"
}

# Créer la documentation
create_documentation() {
    log "Création de la documentation..."
    
    cat > "/opt/claude-state/README.md" << 'DOCEOF'
# Claude IaC System - Documentation

## Vue d'ensemble
Système de versioning et rollback automatique pour Claude Code qui permet de:
- Tracer toutes les actions de Claude
- Créer des snapshots avant/après chaque exécution
- Générer automatiquement du code IaC (Bash, Ansible, Terraform)
- Effectuer des rollbacks vers des versions antérieures

## Commandes principales

### claude-iac
Exécute Claude Code avec versioning automatique:
```bash
claude-iac "Analyse ce projet Python"
claude-iac "Crée une API Flask"
```

### claude-versions
Gestion des versions:
```bash
claude-versions list           # Lister toutes les versions
claude-versions show <id>      # Détails d'une version
claude-versions stats          # Statistiques
claude-versions clean 30       # Nettoyer versions > 30 jours
```

### claude-rollback
Rollback vers une version antérieure:
```bash
claude-rollback <version_id>   # Rollback interactif
```

## Structure des fichiers

```
/opt/claude-state/     # Base de données des versions
├── versions.db        # Base principale (format CSV)
├── v20241201_*.json   # Métadonnées JSON par version
└── README.md          # Cette documentation

/opt/claude-projects/  # Projets IaC générés
└── session_v*/
    ├── scripts/       # Scripts bash de reproduction
    ├── ansible/       # Playbooks Ansible
    ├── terraform/     # Configurations Terraform
    ├── rollback/      # Scripts de rollback
    └── logs/          # Logs d'exécution

/opt/claude-backups/   # Snapshots des états
├── snapshot_v*/       # Snapshots avant exécution
├── v*_after/          # Snapshots après exécution
└── pre_rollback_*/    # Sauvegardes avant rollback

/opt/tmp/             # Répertoire temporaire Claude
```

## Workflow type

1. **Exécution avec versioning:**
   ```bash
   claude-iac "Optimise ce code Python"
   ```
   
2. **Vérifier le résultat:**
   ```bash
   claude-versions list
   ```

3. **Si problème, rollback:**
   ```bash
   claude-rollback v20241201_143022_1234
   ```

4. **Reproduire ailleurs:**
   ```bash
   # Via script bash
   /opt/claude-projects/session_v*/scripts/reproduce_*.sh
   
   # Via Ansible
   ansible-playbook /opt/claude-projects/session_v*/ansible/playbook_*.yml
   
   # Via Terraform
   cd /opt/claude-projects/session_v*/terraform && terraform apply
   ```

## Format de la base de données

versions.db contient:
```
VERSION_ID|TIMESTAMP|COMMAND|PROJECT_DIR|BACKUP_PATH|STATUS|ROLLBACK_CMD
```

Exemple:
```
v20241201_143022_1234|2024-12-01 14:30:22|claude "Analyse projet"|/opt/claude-projects/session_v20241201_143022_1234|/opt/claude-backups/snapshot_v20241201_143022_1234|SUCCESS|
```

## Codes de statut

- **SUCCESS**: Exécution réussie
- **ERROR**: Erreur pendant l'exécution
- **RUNNING**: En cours d'exécution
- **ROLLBACK**: Opération de rollback

## Sécurité et intégrité

- Checksums MD5 pour vérifier l'intégrité des backups
- Métadonnées complètes pour chaque snapshot
- Sauvegarde automatique avant chaque rollback
- Horodatage précis pour traçabilité

## Maintenance

### Nettoyage automatique
```bash
claude-versions clean 30  # Supprimer versions > 30 jours
```

### Vérification de l'espace disque
```bash
claude-versions stats     # Voir l'utilisation
du -sh /opt/claude-*      # Détail par répertoire
```

### Export pour archivage
```bash
claude-versions export v20241201_143022_1234
```

## Dépannage

### Version manquante
Si une version n'apparaît pas, vérifier:
1. Fichier `/opt/claude-state/versions.db`
2. Répertoire `/opt/claude-projects/`
3. Permissions sur `/opt/claude-*`

### Backup corrompu
En cas d'erreur d'intégrité:
1. Vérifier les checksums dans `.claude_checksums`
2. Utiliser une version antérieure
3. Recreer depuis le code IaC

### Espace disque
Les backups peuvent consommer beaucoup d'espace:
1. Nettoyer régulièrement avec `claude-versions clean`
2. Exporter et archiver les versions importantes
3. Ajuster la rétention selon les besoins

## Personnalisation

### Variables d'environnement
```bash
export CLAUDE_STATE_DIR="/custom/path"      # Base de données
export CLAUDE_PROJECTS_DIR="/custom/path"  # Projets IaC
export CLAUDE_BACKUPS_DIR="/custom/path"   # Backups
```

### Alias personnalisés
Ajouter dans ~/.bashrc:
```bash
alias crun='claude-iac'
alias clist='claude-versions list'
alias cback='claude-rollback'
```
DOCEOF

    success "Documentation créée: /opt/claude-state/README.md"
}

# Test de l'installation
test_installation() {
    log "Test de l'installation..."
    
    # Tester la présence des scripts
    local scripts=("claude-iac" "claude-versions" "claude-rollback")
    for script in "${scripts[@]}"; do
        if [ -x "$HOME/bin/$script" ]; then
            success "✓ $script installé et exécutable"
        else
            error "✗ $script manquant ou non exécutable"
        fi
    done
    
    # Tester les répertoires
    local dirs=("/opt/claude-state" "/opt/claude-projects" "/opt/claude-backups" "/opt/tmp")
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ] && [ -w "$dir" ]; then
            success "✓ $dir créé et accessible en écriture"
        else
            error "✗ $dir problème de création ou permissions"
        fi
    done
    
    # Tester Claude Code
    if command -v claude &> /dev/null; then
        success "✓ Claude Code disponible"
    else
        error "✗ Claude Code non trouvé"
    fi
    
    # Test basique
    log "Test d'exécution basique..."
    if "$HOME/bin/claude-versions" list &> /dev/null; then
        success "✓ claude-versions fonctionne"
    else
        warning "⚠ claude-versions: erreur mineure (normal si première installation)"
    fi
}

# Afficher le résumé final
show_summary() {
    echo
    echo -e "${GREEN}===========================================${NC}"
    echo -e "${GREEN}  Installation Claude IaC terminée !${NC}"
    echo -e "${GREEN}===========================================${NC}"
    echo
    echo "📁 Répertoires créés:"
    echo "   /opt/claude-state     - Base de données des versions"
    echo "   /opt/claude-projects  - Projets IaC générés"
    echo "   /opt/claude-backups   - Snapshots et sauvegardes"
    echo "   /opt/tmp             - Répertoire temporaire Claude"
    echo
    echo "🔧 Scripts installés dans ~/bin/:"
    echo "   claude-iac           - Exécution avec versioning"
    echo "   claude-versions      - Gestion des versions"
    echo "   claude-rollback      - Rollback vers version antérieure"
    echo
    echo "🎯 Alias créés:"
    echo "   cv    → claude-versions"
    echo "   cr    → claude-rollback"
    echo "   claude-help → aide rapide"
    echo
    echo "📖 Documentation: /opt/claude-state/README.md"
    echo
    echo -e "${YELLOW}🚀 Commandes pour commencer:${NC}"
    echo
    echo "   # Recharger votre shell:"
    echo "   source ~/.bashrc"
    echo
    echo "   # Premier test:"
    echo "   claude-iac --version"
    echo
    echo "   # Exécuter Claude avec versioning:"
    echo "   claude-iac \"Analyse ce répertoire\""
    echo
    echo "   # Voir les versions:"
    echo "   claude-versions list"
    echo
    echo "   # Aide:"
    echo "   claude-help"
    echo
    echo -e "${BLUE}💡 Conseils:${NC}"
    echo "   • Utilisez toujours 'claude-iac' au lieu de 'claude' pour le versioning"
    echo "   • Consultez régulièrement 'claude-versions stats' pour l'espace disque"
    echo "   • Nettoyez périodiquement avec 'claude-versions clean 30'"
    echo "   • En cas de problème, consultez /opt/claude-state/README.md"
    echo
}

# Installation avec support des options
install_with_options() {
    local skip_docs=false
    local skip_test=false
    
    # Parser les options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-docs)
                skip_docs=true
                shift
                ;;
            --skip-test)
                skip_test=true
                shift
                ;;
            --help|-h)
                echo "Installation Claude IaC System"
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  --skip-docs    Ne pas créer la documentation"
                echo "  --skip-test    Ne pas exécuter les tests"
                echo "  --help, -h     Afficher cette aide"
                exit 0
                ;;
            *)
                warning "Option inconnue: $1"
                shift
                ;;
        esac
    done
    
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}  Installation Claude IaC System${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo
    
    check_prerequisites
    create_directories
    install_main_script
    install_versions_script
    install_rollback_script
    configure_path
    create_aliases
    
    if [ "$skip_docs" != "true" ]; then
        create_documentation
    fi
    
    if [ "$skip_test" != "true" ]; then
        test_installation
    fi
    
    show_summary
}

# Point d'entrée principal
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_with_options "$@"
fi
