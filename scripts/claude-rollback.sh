#!/bin/bash
# Rollback
# Script de rollback pour Claude IaC
# Fichier: scripts/claude-rollback.sh

set -e

# Configuration
CLAUDE_STATE_DIR="/opt/claude-state"
CLAUDE_BACKUPS_DIR="/opt/claude-backups"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

# Afficher l'aide
show_usage() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    CLAUDE ROLLBACK                        ║${NC}"
    echo -e "${CYAN}║                Rollback vers version antérieure           ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "Usage: claude-rollback [OPTIONS] <version_id>"
    echo
    echo "Options:"
    echo "  -f, --force          Forcer le rollback sans confirmation"
    echo "  -d, --dry-run        Simulation sans exécution réelle"
    echo "  -l, --list           Lister les versions disponibles pour rollback"
    echo "  -i, --info <id>      Afficher les informations d'une version"
    echo "  -h, --help           Afficher cette aide"
    echo
    echo "Exemples:"
    echo "  claude-rollback v20241201_143022_1234"
    echo "  claude-rollback --dry-run v20241201_143022_1234"
    echo "  claude-rollback --list"
    echo "  claude-rollback --info v20241201_143022_1234"
    echo
    echo "Notes:"
    echo "  • Un backup de l'état actuel est créé avant chaque rollback"
    echo "  • L'intégrité des backups est vérifiée avant restauration"
    echo "  • Les rollbacks sont eux-mêmes versionnés pour traçabilité"
}

# Lister les versions disponibles pour rollback
list_rollback_versions() {
    echo -e "${CYAN}═══ VERSIONS DISPONIBLES POUR ROLLBACK ═══${NC}"
    echo
    
    if [ ! -f "$CLAUDE_STATE_DIR/versions.db" ]; then
        warning "Aucune version trouvée dans la base de données."
        echo "Vérifiez que Claude IaC a été utilisé au moins une fois."
        return 1
    fi
    
    printf "%-20s %-19s %-10s %-15s %-30s\n" "VERSION_ID" "TIMESTAMP" "STATUS" "BACKUP_STATUS" "COMMAND"
    printf "%-20s %-19s %-10s %-15s %-30s\n" "----------" "---------" "------" "-------------" "-------"
    
    local count=0
    while IFS='|' read -r version_id timestamp command project_dir backup_path status rollback_cmd; do
        # Ignorer les commentaires et lignes vides
        if [[ "$version_id" == \#* ]] || [[ -z "$version_id" ]]; then
            continue
        fi
        
        # Vérifier si le backup existe et est valide
        local backup_status
        if [ -d "$backup_path" ] && [ -n "$backup_path" ]; then
            if [ -f "$backup_path/.claude_metadata" ]; then
                backup_status="${GREEN}Disponible${NC}"
            else
                backup_status="${YELLOW}Incomplet${NC}"
            fi
        else
            backup_status="${RED}Manquant${NC}"
        fi
        
        # Couleur selon le statut de la version
        local status_color
        case "$status" in
            "SUCCESS") status_color="$GREEN" ;;
            "ERROR") status_color="$RED" ;;
            "RUNNING") status_color="$YELLOW" ;;
            *) status_color="$NC" ;;
        esac
        
        # Tronquer la commande si trop longue
        local short_command=$(echo "$command" | cut -c1-27)
        if [ ${#command} -gt 27 ]; then
            short_command="${short_command}..."
        fi
        
        printf "${status_color}%-20s${NC} %-19s ${status_color}%-10s${NC} %-15s %-30s\n" \
            "$version_id" \
            "$(echo "$timestamp" | cut -c1-19)" \
            "$status" \
            "$backup_status" \
            "$short_command"
            
        ((count++))
    done < "$CLAUDE_STATE_DIR/versions.db"
    
    echo
    if [ $count -eq 0 ]; then
        warning "Aucune version trouvée dans la base de données."
    else
        echo -e "${BLUE}Total: $count versions${NC}"
        echo
        echo -e "${YELLOW}💡 Conseils:${NC}"
        echo "  • Utilisez --info <version_id> pour voir les détails"
        echo "  • Seules les versions avec backup 'Disponible' peuvent être restaurées"
        echo "  • Les versions SUCCESS sont généralement plus sûres pour le rollback"
    fi
}

# Afficher les informations détaillées d'une version
show_version_info() {
    local version_id="$1"
    
    if [ -z "$version_id" ]; then
        error "Version ID requis pour --info"
        return 1
    fi
    
    # Vérifier que la version existe
    if ! grep -q "^${version_id}|" "$CLAUDE_STATE_DIR/versions.db" 2>/dev/null; then
        error "Version $version_id non trouvée dans la base de données"
        return 1
    fi
    
    echo -e "${CYAN}═══ INFORMATIONS VERSION $version_id ═══${NC}"
    echo
    
    # Récupérer les informations de la version
    local version_line=$(grep "^${version_id}|" "$CLAUDE_STATE_DIR/versions.db")
    IFS='|' read -r vid timestamp command project_dir backup_path status rollback_cmd <<< "$version_line"
    
    echo -e "${WHITE}Version:${NC} $vid"
    echo -e "${WHITE}Timestamp:${NC} $timestamp"
    echo -e "${WHITE}Status:${NC} $status"
    echo -e "${WHITE}Commande:${NC} $command"
    echo -e "${WHITE}Projet IaC:${NC} $project_dir"
    echo -e "${WHITE}Backup:${NC} $backup_path"
    echo
    
    # Vérifier l'état du backup
    echo -e "${YELLOW}═══ ÉTAT DU BACKUP ═══${NC}"
    
    if [ ! -d "$backup_path" ]; then
        error "✗ Répertoire de backup manquant: $backup_path"
        return 1
    fi
    
    success "✓ Répertoire de backup présent"
    
    # Vérifier les métadonnées
    local metadata_file="$backup_path/.claude_metadata"
    if [ -f "$metadata_file" ]; then
        success "✓ Métadonnées présentes"
        echo
        echo -e "${YELLOW}Métadonnées du backup:${NC}"
        while IFS='=' read -r key value; do
            echo "  $key: $value"
        done < "$metadata_file"
    else
        error "✗ Métadonnées manquantes"
        return 1
    fi
    
    # Vérifier les checksums
    local checksums_file="$backup_path/.claude_checksums"
    if [ -f "$checksums_file" ]; then
        success "✓ Checksums présents"
        
        # Tester l'intégrité
        echo -n "  Vérification de l'intégrité... "
        cd "$backup_path"
        if md5sum -c .claude_checksums --quiet 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}ERREUR${NC}"
            warning "⚠ L'intégrité du backup peut être compromise"
        fi
        cd - > /dev/null
    else
        warning "⚠ Checksums manquants (backup plus ancien)"
    fi
    
    # Informations sur la taille
    echo
    echo -e "${YELLOW}═══ STATISTIQUES ═══${NC}"
    local backup_size=$(du -sh "$backup_path" 2>/dev/null | cut -f1 || echo "N/A")
    local file_count=$(find "$backup_path" -type f 2>/dev/null | wc -l || echo "0")
    
    echo "  Taille du backup: $backup_size"
    echo "  Nombre de fichiers: $file_count"
    
    # Vérifier s'il y a des projets IaC disponibles
    echo
    echo -e "${YELLOW}═══ FICHIERS IaC DISPONIBLES ═══${NC}"
    
    if [ -d "$project_dir" ]; then
        success "✓ Projet IaC disponible: $project_dir"
        
        # Scripts de reproduction
        if [ -d "$project_dir/scripts" ]; then
            echo "  Scripts de reproduction:"
            find "$project_dir/scripts" -name "*.sh" -type f 2>/dev/null | sed 's/^/    /'
        fi
        
        # Playbooks Ansible
        if [ -d "$project_dir/ansible" ]; then
            echo "  Playbooks Ansible:"
            find "$project_dir/ansible" -name "*.yml" -type f 2>/dev/null | sed 's/^/    /'
        fi
        
        # Configurations Terraform
        if [ -d "$project_dir/terraform" ]; then
            echo "  Configurations Terraform:"
            find "$project_dir/terraform" -name "*.tf" -type f 2>/dev/null | sed 's/^/    /'
        fi
    else
        warning "⚠ Projet IaC non trouvé: $project_dir"
    fi
    
    echo
    echo -e "${GREEN}Cette version est prête pour le rollback.${NC}"
}

# Effectuer le rollback
perform_rollback() {
    local version_id="$1"
    local force_mode="$2"
    local dry_run="$3"
    
    if [ -z "$version_id" ]; then
        error "Version ID requis pour le rollback"
        show_usage
        return 1
    fi
    
    log "Démarrage du rollback vers la version $version_id"
    
    # Vérifier que la version existe
    if ! grep -q "^${version_id}|" "$CLAUDE_STATE_DIR/versions.db" 2>/dev/null; then
        error "Version $version_id non trouvée dans la base de données"
        echo "Utilisez --list pour voir les versions disponibles"
        return 1
    fi
    
    # Récupérer les informations de la version
    local version_line=$(grep "^${version_id}|" "$CLAUDE_STATE_DIR/versions.db")
    IFS='|' read -r vid timestamp command project_dir backup_path status rollback_cmd <<< "$version_line"
    
    # Vérifications préalables
    log "Vérifications préalables..."
    
    if [ ! -d "$backup_path" ]; then
        error "Backup non trouvé: $backup_path"
        echo "Cette version ne peut pas être restaurée."
        return 1
    fi
    
    local metadata_file="$backup_path/.claude_metadata"
    if [ ! -f "$metadata_file" ]; then
        error "Métadonnées manquantes dans le backup"
        echo "Le backup semble incomplet ou corrompu."
        return 1
    fi
    
    # Charger les métadonnées
    source "$metadata_file"
    
    # Afficher les informations du rollback
    echo
    echo -e "${BLUE}═══ INFORMATIONS ROLLBACK ═══${NC}"
    echo -e "${WHITE}Version cible:${NC} $version_id"
    echo -e "${WHITE}Timestamp:${NC} $timestamp"
    echo -e "${WHITE}Commande originale:${NC} $command"
    echo -e "${WHITE}Chemin de restauration:${NC} $ORIGINAL_PATH"
    echo -e "${WHITE}Source backup:${NC} $backup_path"
    echo -e "${WHITE}Utilisateur original:${NC} $USER"
    echo -e "${WHITE}Hostname original:${NC} $HOSTNAME"
    echo
    
    if [ "$dry_run" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN] Actions qui seraient effectuées:${NC}"
        echo "1. Vérification de l'intégrité du backup"
        echo "2. Création d'un backup de l'état actuel dans:"
        echo "   $CLAUDE_BACKUPS_DIR/pre_rollback_$(date +%Y%m%d_%H%M%S)"
        echo "3. Suppression du contenu actuel: $ORIGINAL_PATH"
        echo "4. Restauration depuis: $backup_path"
        echo "5. Nettoyage des fichiers de métadonnées"
        echo "6. Enregistrement du rollback dans la base de données"
        echo
        echo -e "${GREEN}Simulation terminée. Utilisez sans --dry-run pour exécuter.${NC}"
        return 0
    fi
    
    # Demander confirmation si pas en mode force
    if [ "$force_mode" != "true" ]; then
        echo -e "${YELLOW}⚠ ATTENTION: Cette action va écraser l'état actuel.${NC}"
        echo -e "${YELLOW}Un backup de l'état actuel sera créé automatiquement.${NC}"
        echo
        read -p "Voulez-vous continuer avec le rollback? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Rollback annulé par l'utilisateur."
            return 0
        fi
    fi
    
    echo
    log "Démarrage du processus de rollback..."
    
    # 1. Vérifier l'intégrité du backup
    if [ -f "$backup_path/.claude_checksums" ]; then
        log "Vérification de l'intégrité du backup..."
        cd "$backup_path"
        if ! md5sum -c .claude_checksums --quiet 2>/dev/null; then
            error "Intégrité du backup compromise"
            echo "Les checksums ne correspondent pas. Le backup peut être corrompu."
            if [ "$force_mode" != "true" ]; then
                echo "Utilisez --force pour ignorer cette vérification (risqué)."
                return 1
            else
                warning "Vérification d'intégrité ignorée (mode --force)"
            fi
        else
            success "✓ Intégrité du backup vérifiée"
        fi
        cd - > /dev/null
    else
        warning "⚠ Checksums non disponibles, continuation sans vérification"
    fi
    
    # 2. Créer un backup de l'état actuel
    local pre_rollback_backup="$CLAUDE_BACKUPS_DIR/pre_rollback_$(date +%Y%m%d_%H%M%S)"
    
    if [ -d "$ORIGINAL_PATH" ]; then
        log "Sauvegarde de l'état actuel..."
        if cp -r "$ORIGINAL_PATH" "$pre_rollback_backup" 2>/dev/null; then
            success "✓ État actuel sauvegardé: $pre_rollback_backup"
            
            # Ajouter des métadonnées au backup pré-rollback
            cat > "$pre_rollback_backup/.claude_metadata" << PREROLLBACK_META
VERSION_ID=pre_rollback_$(date +%Y%m%d_%H%M%S)
TIMESTAMP=$(date)
ORIGINAL_PATH=$ORIGINAL_PATH
USER=$(whoami)
HOSTNAME=$(hostname)
PWD=$(pwd)
ROLLBACK_SOURCE=$version_id
ROLLBACK_REASON=Backup before rollback to $version_id
PREROLLBACK_META
            
        else
            error "Échec de la sauvegarde de l'état actuel"
            echo "Le rollback ne peut pas continuer sans backup de sécurité."
            return 1
        fi
    else
        warning "⚠ Répertoire cible non existant: $ORIGINAL_PATH"
        log "Aucun backup de l'état actuel nécessaire"
    fi
    
    # 3. Restaurer depuis le backup
    log "Restauration en cours..."
    
    # Supprimer le contenu existant
    if [ -d "$ORIGINAL_PATH" ]; then
        if rm -rf "$ORIGINAL_PATH" 2>/dev/null; then
            log "Contenu existant supprimé"
        else
            error "Impossible de supprimer le contenu existant: $ORIGINAL_PATH"
            return 1
        fi
    fi
    
    # Créer le répertoire parent si nécessaire
    local parent_dir=$(dirname "$ORIGINAL_PATH")
    if [ ! -d "$parent_dir" ]; then
        mkdir -p "$parent_dir" || {
            error "Impossible de créer le répertoire parent: $parent_dir"
            return 1
        }
    fi
    
    # Copier le backup
    if cp -r "$backup_path" "$ORIGINAL_PATH" 2>/dev/null; then
        success "✓ Contenu restauré depuis le backup"
    else
        error "Échec de la restauration"
        
        # Tentative de récupération
        if [ -d "$pre_rollback_backup" ]; then
            warning "Tentative de récupération..."
            cp -r "$pre_rollback_backup" "$ORIGINAL_PATH" 2>/dev/null || true
        fi
        return 1
    fi
    
    # 4. Nettoyer les métadonnées
    rm -f "$ORIGINAL_PATH/.claude_metadata" "$ORIGINAL_PATH/.claude_checksums" 2>/dev/null || true
    
    # 5. Enregistrer le rollback dans la base de données
    local rollback_id="rollback_$(date +%Y%m%d_%H%M%S)"
    local rollback_entry="${rollback_id}|$(date)|ROLLBACK to ${version_id}|${ORIGINAL_PATH}|${pre_rollback_backup}|SUCCESS|"
    
    echo "$rollback_entry" >> "$CLAUDE_STATE_DIR/versions.db"
    
    # Créer le fichier JSON pour ce rollback
    cat > "$CLAUDE_STATE_DIR/${rollback_id}.json" << ROLLBACK_JSON
{
    "version_id": "$rollback_id",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "command": "ROLLBACK to ${version_id}",
    "project_directory": "$ORIGINAL_PATH",
    "backup_path": "$pre_rollback_backup",
    "status": "SUCCESS",
    "rollback_command": "",
    "user": "$(whoami)",
    "hostname": "$(hostname)",
    "working_directory": "$(pwd)",
    "rollback_source": "$version_id",
    "original_timestamp": "$timestamp",
    "original_command": "$command"
}
ROLLBACK_JSON
    
    echo
    success "🎉 Rollback terminé avec succès !"
    echo
    echo -e "${GREEN}═══ RÉSUMÉ ═══${NC}"
    echo -e "${WHITE}Version restaurée:${NC} $version_id"
    echo -e "${WHITE}Date originale:${NC} $(date -d "$timestamp" 2>/dev/null || echo "$timestamp")"
    echo -e "${WHITE}Commande originale:${NC} $command"
    echo -e "${WHITE}Chemin restauré:${NC} $ORIGINAL_PATH"
    echo -e "${WHITE}Backup pré-rollback:${NC} $pre_rollback_backup"
    echo -e "${WHITE}ID du rollback:${NC} $rollback_id"
    echo
    echo -e "${BLUE}💡 Actions possibles:${NC}"
    echo -e "  • Vérifier que la restauration est correcte"
    echo -e "  • Pour annuler ce rollback: ${YELLOW}claude-rollback $rollback_id${NC}"
    echo -e "  • Voir l'historique: ${YELLOW}claude-versions list${NC}"
    echo -e "  • Nettoyer les anciens backups: ${YELLOW}claude-versions clean${NC}"
}

# Parser les arguments
parse_arguments() {
    local force_mode=false
    local dry_run=false
    local version_id=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force_mode=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -l|--list)
                list_rollback_versions
                exit 0
                ;;
            -i|--info)
                if [[ -n "$2" && "$2" != -* ]]; then
                    show_version_info "$2"
                    exit 0
                else
                    error "Option --info nécessite un version_id"
                    exit 1
                fi
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                error "Option inconnue: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$version_id" ]]; then
                    version_id="$1"
                else
                    error "Plusieurs version_id spécifiés"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Si aucun argument, afficher l'aide
    if [[ -z "$version_id" && "$force_mode" == false && "$dry_run" == false ]]; then
        show_usage
        exit 1
    fi
    
    # Exécuter le rollback
    perform_rollback "$version_id" "$force_mode" "$dry_run"
}

# Vérifications initiales
check_prerequisites() {
    # Vérifier que les répertoires existent
    if [ ! -d "$CLAUDE_STATE_DIR" ]; then
        error "Répertoire Claude State non trouvé: $CLAUDE_STATE_DIR"
        echo "Assurez-vous que Claude IaC est installé correctement."
        exit 1
    fi
    
    if [ ! -d "$CLAUDE_BACKUPS_DIR" ]; then
        error "Répertoire Claude Backups non trouvé: $CLAUDE_BACKUPS_DIR"
        echo "Assurez-vous que Claude IaC est installé correctement."
        exit 1
    fi
    
    # Vérifier la base de données
    if [ ! -f "$CLAUDE_STATE_DIR/versions.db" ]; then
        warning "Base de données des versions non trouvée"
        echo "Il semble qu'aucune version n'ait été créée avec Claude IaC."
        echo "Utilisez 'claude-iac' pour créer votre première version."
        exit 1
    fi
}

# Point d'entrée principal
main() {
    # Vérifier les prérequis
    check_prerequisites
    
    # Parser et exécuter
    parse_arguments "$@"
}

# Exécuter si script appelé directement
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
