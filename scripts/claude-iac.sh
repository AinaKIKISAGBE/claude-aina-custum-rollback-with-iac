#!/bin/bash
# Script principal
# Claude IaC System avec Versioning et Rollback
# Créer ce script en tant que ~/bin/claude-iac


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
NC='\033[0m' # No Color

# Fonctions utilitaires
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
    log "Initialisation des répertoires..."
    sudo mkdir -p "$CLAUDE_STATE_DIR" "$CLAUDE_PROJECTS_DIR" "$CLAUDE_BACKUPS_DIR"
    sudo chown $USER:$USER "$CLAUDE_STATE_DIR" "$CLAUDE_PROJECTS_DIR" "$CLAUDE_BACKUPS_DIR"
    
    # Créer la base de données des versions si elle n'existe pas
    if [ ! -f "$CLAUDE_STATE_DIR/versions.db" ]; then
        cat > "$CLAUDE_STATE_DIR/versions.db" << EOF
# Claude IaC Versions Database
# Format: VERSION_ID|TIMESTAMP|COMMAND|PROJECT_DIR|BACKUP_PATH|STATUS|ROLLBACK_CMD
EOF
    fi
}

# Créer un snapshot de l'état actuel
create_snapshot() {
    local version_id="$1"
    local project_path="$2"
    local backup_path="$CLAUDE_BACKUPS_DIR/snapshot_${version_id}"
    
    log "Création du snapshot pour $version_id..."
    
    if [ -d "$project_path" ]; then
        # Créer une copie complète du projet
        cp -r "$project_path" "$backup_path"
        
        # Sauvegarder les métadonnées
        cat > "$backup_path/.claude_metadata" << EOF
VERSION_ID=$version_id
TIMESTAMP=$(date)
ORIGINAL_PATH=$project_path
USER=$(whoami)
HOSTNAME=$(hostname)
PWD=$(pwd)
EOF
        
        # Calculer le hash pour vérification d'intégrité
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
    
    # Créer aussi un fichier JSON pour faciliter l'analyse
    cat > "$CLAUDE_STATE_DIR/${version_id}.json" << EOF
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
EOF
}

# Générer le code IaC pour cette session
generate_iac() {
    local version_id="$1"
    local project_dir="$2"
    local command="$3"
    
    # Créer le répertoire du projet pour cette version
    mkdir -p "$project_dir"/{logs,scripts,ansible,terraform,docker,rollback}
    
    # Générer le script de reproduction
    cat > "$project_dir/scripts/reproduce_${version_id}.sh" << SCRIPT_EOF
#!/bin/bash
# Script de reproduction pour $version_id
# Généré le $(date)

set -e

echo "=== Reproduction de $version_id ==="
echo "Commande originale: $command"
echo "Répertoire: $(pwd)"
echo

# Configuration de l'environnement
export TMPDIR=/opt/tmp
export TEMP=/opt/tmp
export TMP=/opt/tmp

# Exécution de la commande
$command

echo "=== Fin de la reproduction ==="
SCRIPT_EOF
    chmod +x "$project_dir/scripts/reproduce_${version_id}.sh"
    
    # Générer le playbook Ansible
    cat > "$project_dir/ansible/playbook_${version_id}.yml" << ANSIBLE_EOF
---
- name: "Reproduire Claude session $version_id"
  hosts: localhost
  gather_facts: yes
  vars:
    version_id: "$version_id"
    original_command: "$command"
    project_dir: "$project_dir"
  
  tasks:
    - name: "Configuration de l'environnement temporaire"
      set_fact:
        temp_dirs:
          - "/opt/tmp"
    
    - name: "Créer les répertoires temporaires"
      file:
        path: "{{ item }}"
        state: directory
        owner: "$USER"
        group: "$USER"
        mode: '0755'
      loop: "{{ temp_dirs }}"
      become: yes
    
    - name: "Exécuter la commande Claude"
      shell: |
        export TMPDIR=/opt/tmp
        export TEMP=/opt/tmp
        export TMP=/opt/tmp
        $command
      register: claude_result
    
    - name: "Afficher le résultat"
      debug:
        var: claude_result.stdout_lines
ANSIBLE_EOF
    
    # Générer la configuration Terraform
    cat > "$project_dir/terraform/main_${version_id}.tf" << TERRAFORM_EOF
# Configuration Terraform pour $version_id
# Généré le $(date)

terraform {
  required_version = ">= 1.0"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Variables
variable "version_id" {
  description = "Version ID de la session Claude"
  type        = string
  default     = "$version_id"
}

variable "project_dir" {
  description = "Répertoire du projet"
  type        = string
  default     = "$project_dir"
}

# Création des répertoires temporaires
resource "null_resource" "setup_temp_dirs" {
  provisioner "local-exec" {
    command = "mkdir -p /opt/tmp && chown $USER:$USER /opt/tmp"
  }
}

# Exécution de la commande Claude
resource "null_resource" "claude_execution" {
  depends_on = [null_resource.setup_temp_dirs]
  
  provisioner "local-exec" {
    command = "export TMPDIR=/opt/tmp && export TEMP=/opt/tmp && export TMP=/opt/tmp && $command"
  }
  
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Nettoyage de la version \${var.version_id}'"
  }
}

# Outputs
output "version_id" {
  value = var.version_id
}

output "execution_time" {
  value = timestamp()
}
TERRAFORM_EOF
    
    # Générer le script de rollback
    generate_rollback_script "$version_id" "$project_dir"
}

# Générer le script de rollback
generate_rollback_script() {
    local version_id="$1"
    local project_dir="$2"
    
    cat > "$project_dir/rollback/rollback_${version_id}.sh" << ROLLBACK_EOF
#!/bin/bash
# Script de rollback pour $version_id

set -e

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
VERSION_ID="$version_id"
BACKUP_PATH="$CLAUDE_BACKUPS_DIR/snapshot_\${VERSION_ID}"

echo "=== Rollback de la version \$VERSION_ID ==="

if [ ! -d "\$BACKUP_PATH" ]; then
    echo "ERREUR: Backup non trouvé pour \$VERSION_ID"
    exit 1
fi

# Vérifier l'intégrité du backup
if [ -f "\$BACKUP_PATH/.claude_checksums" ]; then
    echo "Vérification de l'intégrité du backup..."
    cd "\$BACKUP_PATH"
    if ! md5sum -c .claude_checksums --quiet; then
        echo "ERREUR: Intégrité du backup compromise"
        exit 1
    fi
    cd - > /dev/null
fi

# Charger les métadonnées
if [ -f "\$BACKUP_PATH/.claude_metadata" ]; then
    source "\$BACKUP_PATH/.claude_metadata"
    echo "Restauration vers: \$ORIGINAL_PATH"
    
    # Créer un backup de l'état actuel avant rollback
    CURRENT_BACKUP="$CLAUDE_BACKUPS_DIR/pre_rollback_\$(date +%Y%m%d_%H%M%S)"
    if [ -d "\$ORIGINAL_PATH" ]; then
        cp -r "\$ORIGINAL_PATH" "\$CURRENT_BACKUP"
        echo "État actuel sauvegardé dans: \$CURRENT_BACKUP"
    fi
    
    # Restaurer
    rm -rf "\$ORIGINAL_PATH"
    cp -r "\$BACKUP_PATH" "\$ORIGINAL_PATH"
    rm -f "\$ORIGINAL_PATH/.claude_metadata" "\$ORIGINAL_PATH/.claude_checksums"
    
    echo "Rollback terminé avec succès"
else
    echo "ERREUR: Métadonnées manquantes"
    exit 1
fi
ROLLBACK_EOF
    chmod +x "$project_dir/rollback/rollback_${version_id}.sh"
}

# Fonction principale d'exécution
execute_claude() {
    local command="claude $*"
    local project_dir="$CLAUDE_PROJECTS_DIR/session_${SESSION_ID}"
    
    log "Démarrage de la session $SESSION_ID"
    log "Commande: $command"
    log "Répertoire de travail: $(pwd)"
    
    # Créer un snapshot de l'état avant
    local backup_path=$(create_snapshot "$SESSION_ID" "$(pwd)")
    
    # Générer le code IaC
    generate_iac "$SESSION_ID" "$project_dir" "$command"
    
    # Créer les logs
    local log_file="$project_dir/logs/execution_${SESSION_ID}.log"
    mkdir -p "$(dirname "$log_file")"
    
    # Enregistrer la version
    register_version "$SESSION_ID" "$command" "$project_dir" "$backup_path" "RUNNING"
    
    log "Exécution de Claude Code..."
    
    # Exécuter Claude et capturer tout
    {
        echo "=== Session Claude Code $SESSION_ID ==="
        echo "Date: $(date)"
        echo "Utilisateur: $(whoami)"
        echo "Hostname: $(hostname)"
        echo "Commande: $command"
        echo "Répertoire: $(pwd)"
        echo "=== Début de l'exécution ==="
        echo
        
        # Exécuter la commande réelle
        if claude "$@"; then
            echo
            echo "=== Fin de l'exécution (SUCCESS) ==="
            register_version "$SESSION_ID" "$command" "$project_dir" "$backup_path" "SUCCESS"
            success "Session terminée avec succès"
        else
            echo
            echo "=== Fin de l'exécution (ERREUR) ==="
            register_version "$SESSION_ID" "$command" "$project_dir" "$backup_path" "ERROR"
            error "Session terminée avec erreur"
        fi
        
    } 2>&1 | tee "$log_file"
    
    # Créer un snapshot de l'état après
    local after_backup=$(create_snapshot "${SESSION_ID}_after" "$(pwd)")
    
    success "Session $SESSION_ID terminée"
    success "Projet IaC: $project_dir"
    success "Logs: $log_file"
    success "Backup avant: $backup_path"
    success "Backup après: $after_backup"
    
    echo
    echo "=== Commandes utiles ==="
    echo "Voir les versions: claude-versions"
    echo "Rollback: claude-rollback $SESSION_ID"
    echo "Reproduire: $project_dir/scripts/reproduce_${SESSION_ID}.sh"
}

# Si appelé directement
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_directories
    execute_claude "$@"
fi
