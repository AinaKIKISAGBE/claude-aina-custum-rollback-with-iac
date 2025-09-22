#!/bin/bash
# =============================================================================
# SCRIPT 1: claude-versions (~/bin/claude-versions)
# =============================================================================
# Gestion versions : claude-versions.sh
# Gestionnaire de versions Claude IaC

CLAUDE_STATE_DIR="/opt/claude-state"
CLAUDE_PROJECTS_DIR="/opt/claude-projects"
CLAUDE_BACKUPS_DIR="/opt/claude-backups"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

show_usage() {
    echo "Usage: claude-versions [OPTION]"
    echo
    echo "Options:"
    echo "  list, ls              Lister toutes les versions"
    echo "  show <version_id>     Afficher les détails d'une version"
    echo "  diff <v1> <v2>        Comparer deux versions"
    echo "  clean [days]          Nettoyer les anciennes versions (défaut: 30 jours)"
    echo "  stats                 Afficher les statistiques"
    echo "  export <version_id>   Exporter une version"
    echo "  -h, --help           Afficher cette aide"
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
            # Formatage des couleurs selon le statut
            case "$status" in
                "SUCCESS") color="$GREEN" ;;
                "ERROR") color="$RED" ;;
                "RUNNING") color="$YELLOW" ;;
                *) color="$NC" ;;
            esac
            
            # Tronquer la commande si trop longue
            short_command=$(echo "$command" | cut -c1-47)
            if [ ${#command} -gt 47 ]; then
                short_command="${short_command}..."
            fi
            
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
    
    echo -e "${CYAN}=== Détails de la version $version_id ===${NC}"
    
    # Utiliser jq si disponible, sinon parser manuellement
    if command -v jq &> /dev/null; then
        jq -r '
            "Timestamp: " + .timestamp,
            "Commande: " + .command,
            "Status: " + .status,
            "Utilisateur: " + .user,
            "Hostname: " + .hostname,
            "Répertoire: " + .working_directory,
            "Projet IaC: " + .project_directory,
            "Backup: " + .backup_path
        ' "$json_file"
    else
        # Parser basique
        grep -o '"[^"]*": *"[^"]*"' "$json_file" | while IFS=': ' read -r key value; do
            key=$(echo "$key" | tr -d '"')
            value=$(echo "$value" | tr -d '"')
            echo "$key: $value"
        done
    fi
    
    # Vérifier l'existence des fichiers
    echo -e "\n${YELLOW}=== État des fichiers ===${NC}"
    
    local project_dir=$(grep '"project_directory"' "$json_file" | cut -d'"' -f4)
    local backup_path=$(grep '"backup_path"' "$json_file" | cut -d'"' -f4)
    
    if [ -d "$project_dir" ]; then
        echo -e "${GREEN}✓${NC} Projet IaC: $project_dir"
        echo "  Scripts:"
        find "$project_dir/scripts" -name "*.sh" -type f 2>/dev/null | sed 's/^/    /'
        echo "  Logs:"
        find "$project_dir/logs" -name "*.log" -type f 2>/dev/null | sed 's/^/    /'
    else
        echo -e "${RED}✗${NC} Projet IaC manquant: $project_dir"
    fi
    
    if [ -d "$backup_path" ] && [ -n "$backup_path" ]; then
        echo -e "${GREEN}✓${NC} Backup disponible: $backup_path"
        local backup_size=$(du -sh "$backup_path" 2>/dev/null | cut -f1)
        echo "    Taille: $backup_size"
    else
        echo -e "${RED}✗${NC} Backup manquant: $backup_path"
    fi
}

diff_versions() {
    local v1="$1"
    local v2="$2"
    
    if [ -z "$v1" ] || [ -z "$v2" ]; then
        echo "Usage: claude-versions diff <version1> <version2>"
        return 1
    fi
    
    local backup1="$CLAUDE_BACKUPS_DIR/snapshot_${v1}"
    local backup2="$CLAUDE_BACKUPS_DIR/snapshot_${v2}"
    
    if [ ! -d "$backup1" ]; then
        echo "Backup pour $v1 non trouvé: $backup1"
        return 1
    fi
    
    if [ ! -d "$backup2" ]; then
        echo "Backup pour $v2 non trouvé: $backup2"
        return 1
    fi
    
    echo -e "${CYAN}=== Différences entre $v1 et $v2 ===${NC}"
    
    if command -v diff &> /dev/null; then
        diff -r "$backup1" "$backup2" --exclude=".claude_*" || true
    else
        echo "Commande 'diff' non disponible."
        echo "Comparaison basique:"
        echo "Fichiers dans $v1:"
        find "$backup1" -type f | wc -l
        echo "Fichiers dans $v2:"
        find "$backup2" -type f | wc -l
    fi
}

show_stats() {
    if [ ! -f "$CLAUDE_STATE_DIR/versions.db" ]; then
        echo "Aucune version trouvée."
        return
    fi
    
    echo -e "${CYAN}=== Statistiques Claude IaC ===${NC}"
    
    local total_versions=$(grep -v "^#" "$CLAUDE_STATE_DIR/versions.db" | grep -c ".*" || echo "0")
    local success_count=$(grep -c "|SUCCESS|" "$CLAUDE_STATE_DIR/versions.db" || echo "0")
    local error_count=$(grep -c "|ERROR|" "$CLAUDE_STATE_DIR/versions.db" || echo "0")
    local running_count=$(grep -c "|RUNNING|" "$CLAUDE_STATE_DIR/versions.db" || echo "0")
    
    echo "Total des versions: $total_versions"
    echo -e "${GREEN}Succès: $success_count${NC}"
    echo -e "${RED}Erreurs: $error_count${NC}"
    echo -e "${YELLOW}En cours: $running_count${NC}"
    
    # Espace disque utilisé
    if [ -d "$CLAUDE_BACKUPS_DIR" ]; then
        local backup_size=$(du -sh "$CLAUDE_BACKUPS_DIR" 2>/dev/null | cut -f1 || echo "N/A")
        echo "Espace backups: $backup_size"
    fi
    
    if [ -d "$CLAUDE_PROJECTS_DIR" ]; then
        local projects_size=$(du -sh "$CLAUDE_PROJECTS_DIR" 2>/dev/null | cut -f1 || echo "N/A")
        echo "Espace projets: $projects_size"
    fi
}

clean_old_versions() {
    local days="${1:-30}"
    
    echo "Nettoyage des versions de plus de $days jours..."
    
    # Trouver et supprimer les anciens backups
    local deleted_count=0
    find "$CLAUDE_BACKUPS_DIR" -maxdepth 1 -type d -name "snapshot_*" -mtime +$days | while read -r backup_dir; do
        echo "Suppression: $backup_dir"
        rm -rf "$backup_dir"
        ((deleted_count++))
    done
    
    # Nettoyer aussi les anciens projets
    find "$CLAUDE_PROJECTS_DIR" -maxdepth 1 -type d -name "session_*" -mtime +$days | while read -r project_dir; do
        echo "Suppression: $project_dir"
        rm -rf "$project_dir"
    done
    
    echo "Nettoyage terminé."
}

export_version() {
    local version_id="$1"
    local export_path="${2:-./claude_export_${version_id}.tar.gz}"
    
    if [ -z "$version_id" ]; then
        echo "Usage: claude-versions export <version_id> [export_path]"
        return 1
    fi
    
    local project_dir="$CLAUDE_PROJECTS_DIR/session_${version_id}"
    local backup_dir="$CLAUDE_BACKUPS_DIR/snapshot_${version_id}"
    local json_file="$CLAUDE_STATE_DIR/${version_id}.json"
    
    echo "Export de la version $version_id..."
    
    # Créer un répertoire temporaire pour l'export
    local temp_dir=$(mktemp -d)
    local export_dir="$temp_dir/claude_version_${version_id}"
    mkdir -p "$export_dir"
    
    # Copier les fichiers
    [ -d "$project_dir" ] && cp -r "$project_dir" "$export_dir/project"
    [ -d "$backup_dir" ] && cp -r "$backup_dir" "$export_dir/backup"
    [ -f "$json_file" ] && cp "$json_file" "$export_dir/metadata.json"
    
    # Créer le README
    cat > "$export_dir/README.md" << EOF
# Claude IaC Export - Version $version_id

Export créé le: $(date)

## Contenu:
- \`project/\`: Projet IaC généré (scripts, Ansible, Terraform)
- \`backup/\`: Snapshot de l'état original
- \`metadata.json\`: Métadonnées de la version

## Utilisation:
1. Reproduire: \`bash project/scripts/reproduce_${version_id}.sh\`
2. Ansible: \`ansible-playbook project/ansible/playbook_${version_id}.yml\`
3. Terraform: \`cd project/terraform && terraform apply\`
4. Rollback: \`bash project/rollback/rollback_${version_id}.sh\`
EOF
    
    # Créer l'archive
    cd "$temp_dir"
    tar -czf "$export_path" "claude_version_${version_id}"
    cd - > /dev/null
    
    # Nettoyer
    rm -rf "$temp_dir"
    
    echo "Export terminé: $export_path"
}

# Script principal
case "$1" in
    "list"|"ls"|"")
        list_versions
        ;;
    "show")
        show_version_details "$2"
        ;;
    "diff")
        diff_versions "$2" "$3"
        ;;
    "stats")
        show_stats
        ;;
    "clean")
        clean_old_versions "$2"
        ;;
    "export")
        export_version "$2" "$3"
        ;;
    "-h"|"--help")
        show_usage
        ;;
    *)
        echo "Option inconnue: $1"
        show_usage
        exit 1
        ;;
esac


# j'ai dejà un fichier claude-rollback.sh donc de le déactive ici
#  Utiliser un bloc : <<'EOF' pour que Tout ce qui est écrit ici
# sera ignoré par le shell,
# comme un commentaire multi-ligne. ( : <<'END' ...... END
: <<'END'
# =============================================================================
# SCRIPT 2: claude-rollback (~/bin/claude-rollback)
# =============================================================================
#!/bin/bash
# Script de rollback pour Claude IaC

CLAUDE_STATE_DIR="/opt/claude-state"
CLAUDE_BACKUPS_DIR="/opt/claude-backups"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_usage() {
    echo "Usage: claude-rollback [OPTIONS] <version_id>"
    echo
    echo "Options:"
    echo "  -f, --force          Forcer le rollback sans confirmation"
    echo "  -d, --dry-run        Simulation sans exécution"
    echo "  -l, --list           Lister les versions disponibles pour rollback"
    echo "  -h, --help           Afficher cette aide"
    echo
    echo "Exemples:"
    echo "  claude-rollback v20241201_143022_1234"
    echo "  claude-rollback --dry-run v20241201_143022_1234"
    echo "  claude-rollback --list"
}

list_rollback_versions() {
    echo -e "${CYAN}=== Versions disponibles pour rollback ===${NC}"
    
    if [ ! -f "$CLAUDE_STATE_DIR/versions.db" ]; then
        echo "Aucune version trouvée."
        return
    fi
    
    printf "%-20s %-19s %-10s %-30s\n" "VERSION_ID" "TIMESTAMP" "STATUS" "BACKUP_STATUS"
    printf "%-20s %-19s %-10s %-30s\n" "----------" "---------" "------" "-------------"
    
    while IFS='|' read -r version_id timestamp command project_dir backup_path status rollback_cmd; do
        if [[ "$version_id" != \#* ]] && [[ -n "$version_id" ]]; then
            # Vérifier si le backup existe
            if [ -d "$backup_path" ] && [ -n "$backup_path" ]; then
                backup_status="${GREEN}Disponible${NC}"
            else
                backup_status="${RED}Manquant${NC}"
            fi
            
            # Couleur selon le statut
            case "$status" in
                "SUCCESS") color="$GREEN" ;;
                "ERROR") color="$RED" ;;
                *) color="$NC" ;;
            esac
            
            printf "${color}%-20s %-19s %-10s${NC} %-30s\n" \
                "$version_id" \
                "$(echo "$timestamp" | cut -c1-19)" \
                "$status" \
                "$backup_status"
        fi
    done < "$CLAUDE_STATE_DIR/versions.db"
}

perform_rollback() {
    local version_id="$1"
    local force="$2"
    local dry_run="$3"
    
    if [ -z "$version_id" ]; then
        echo -e "${RED}Erreur: Version ID requis${NC}"
        show_usage
        return 1
    fi
    
    # Vérifier que la version existe
    if ! grep -q "^${version_id}|" "$CLAUDE_STATE_DIR/versions.db" 2>/dev/null; then
        echo -e "${RED}Erreur: Version $version_id non trouvée${NC}"
        return 1
    fi
    
    # Récupérer les informations de la version
    local version_line=$(grep "^${version_id}|" "$CLAUDE_STATE_DIR/versions.db")
    IFS='|' read -r vid timestamp command project_dir backup_path status rollback_cmd <<< "$version_line"
    
    local backup_dir="$backup_path"
    
    if [ ! -d "$backup_dir" ]; then
        echo -e "${RED}Erreur: Backup non trouvé pour $version_id${NC}"
        echo "Chemin attendu: $backup_dir"
        return 1
    fi
    
    # Charger les métadonnées du backup
    local metadata_file="$backup_dir/.claude_metadata"
    if [ ! -f "$metadata_file" ]; then
        echo -e "${RED}Erreur: Métadonnées manquantes dans le backup${NC}"
        return 1
    fi
    
    source "$metadata_file"
    
    echo -e "${BLUE}=== Rollback vers $version_id ===${NC}"
    echo "Timestamp: $timestamp"
    echo "Commande originale: $command"
    echo "Chemin de restauration: $ORIGINAL_PATH"
    echo "Backup source: $backup_dir"
    echo
    
    if [ "$dry_run" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN] Actions qui seraient effectuées:${NC}"
        echo "1. Vérification de l'intégrité du backup"
        echo "2. Création d'un backup de l'état actuel"
        echo "3. Suppression de: $ORIGINAL_PATH"
        echo "4. Restauration depuis: $backup_dir"
        echo "5. Nettoyage des fichiers de métadonnées"
        return 0
    fi
    
    # Demander confirmation si pas forcé
    if [ "$force" != "true" ]; then
        echo -e "${YELLOW}Attention: Cette action va écraser l'état actuel.${NC}"
        read -p "Continuer? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Rollback annulé."
            return 0
        fi
    fi
    
    echo -e "${BLUE}Démarrage du rollback...${NC}"
    
    # 1. Vérifier l'intégrité du backup
    if [ -f "$backup_dir/.claude_checksums" ]; then
        echo "Vérification de l'intégrité du backup..."
        cd "$backup_dir"
        if ! md5sum -c .claude_checksums --quiet; then
            echo -e "${RED}Erreur: Intégrité du backup compromise${NC}"
            return 1
        fi
        cd - > /dev/null
        echo -e "${GREEN}✓${NC} Intégrité vérifiée"
    else
        echo -e "${YELLOW}⚠${NC} Pas de checksums disponibles, continuation..."
    fi
    
    # 2. Créer un backup de l'état actuel
    local pre_rollback_backup="$CLAUDE_BACKUPS_DIR/pre_rollback_$(date +%Y%m%d_%H%M%S)"
    if [ -d "$ORIGINAL_PATH" ]; then
        echo "Sauvegarde de l'état actuel..."
        cp -r "$ORIGINAL_PATH" "$pre_rollback_backup"
        echo -e "${GREEN}✓${NC} État actuel sauvegardé: $pre_rollback_backup"
    fi
    
    # 3. Restaurer depuis le backup
    echo "Restauration en cours..."
    if [ -d "$ORIGINAL_PATH" ]; then
        rm -rf "$ORIGINAL_PATH"
    fi
    
    mkdir -p "$(dirname "$ORIGINAL_PATH")"
    cp -r "$backup_dir" "$ORIGINAL_PATH"
    
    # 4. Nettoyer les métadonnées
    rm -f "$ORIGINAL_PATH/.claude_metadata" "$ORIGINAL_PATH/.claude_checksums"
    
    # 5. Enregistrer le rollback
    local rollback_id="rollback_$(date +%Y%m%d_%H%M%S)"
    echo "${rollback_id}|$(date)|ROLLBACK to ${version_id}|${ORIGINAL_PATH}|${pre_rollback_backup}|SUCCESS|" >> "$CLAUDE_STATE_DIR/versions.db"
    
    echo -e "${GREEN}✓ Rollback terminé avec succès${NC}"
    echo "Version restaurée: $version_id"
    echo "Backup de l'état précédent: $pre_rollback_backup"
    
    # Afficher un résumé
    echo
    echo -e "${BLUE}=== Résumé ===${NC}"
    echo "État restauré vers: $(date -d "$timestamp" 2>/dev/null || echo "$timestamp")"
    echo "Commande originale: $command"
    echo "Pour annuler ce rollback: claude-rollback $rollback_id"
}

# Script principal
case "$1" in
    "-l"|"--list")
        list_rollback_versions
        ;;
    "-h"|"--help")
        show_usage
        ;;
    "-d"|"--dry-run")
        perform_rollback "$2" "false" "true"
        ;;
    "-f"|"--force")
        perform_rollback "$2" "true" "false"
        ;;
    -*)
        echo "Option inconnue: $1"
        show_usage
        exit 1
        ;;
    "")
        echo "Version ID requis"
        show_usage
        exit 1
        ;;
    *)
        perform_rollback "$1" "false" "false"
        ;;
esac
END
