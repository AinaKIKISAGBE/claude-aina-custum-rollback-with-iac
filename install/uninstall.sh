#!/bin/bash
# Désinstallation
# Script de désinstallation pour Claude IaC avec Versioning et Rollback

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

question() {
    echo -e "${PURPLE}[QUESTION]${NC} $1"
}

# Afficher l'aide
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options de désinstallation Claude IaC:"
    echo "  --keep-data          Conserver les données (versions, backups, projets)"
    echo "  --keep-config        Conserver la configuration (~/.bashrc)"
    echo "  --force              Désinstallation sans confirmation"
    echo "  --backup-data        Créer une sauvegarde avant suppression"
    echo "  --dry-run            Simuler sans exécuter"
    echo "  --help, -h           Afficher cette aide"
    echo
    echo "Exemples:"
    echo "  $0                           # Désinstallation interactive"
    echo "  $0 --keep-data               # Supprimer scripts mais garder données"
    echo "  $0 --backup-data --force     # Sauvegarder et supprimer sans confirmation"
    echo "  $0 --dry-run                 # Voir ce qui serait supprimé"
}

# Vérifier l'installation existante
check_installation() {
    log "Vérification de l'installation Claude IaC..."
    
    local installed=false
    
    # Vérifier les scripts
    local scripts=("claude-iac" "claude-versions" "claude-rollback")
    for script in "${scripts[@]}"; do
        if [ -f "$HOME/bin/$script" ]; then
            installed=true
            break
        fi
    done
    
    # Vérifier les répertoires
    local dirs=("/opt/claude-state" "/opt/claude-projects" "/opt/claude-backups")
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            installed=true
            break
        fi
    done
    
    if [ "$installed" = false ]; then
        warning "Aucune installation Claude IaC détectée."
        echo "Rien à désinstaller."
        exit 0
    fi
    
    success "Installation Claude IaC détectée"
}

# Afficher un résumé de ce qui sera supprimé
show_removal_summary() {
    local keep_data="$1"
    local keep_config="$2"
    local dry_run="$3"
    
    echo
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}        RÉSUMÉ DE LA DÉSINSTALLATION${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo
    
    # Scripts qui seront supprimés
    echo -e "${YELLOW}Scripts à supprimer:${NC}"
    local scripts=("claude-iac" "claude-versions" "claude-rollback" "claude-help")
    for script in "${scripts[@]}"; do
        if [ -f "$HOME/bin/$script" ]; then
            echo "  ✗ $HOME/bin/$script"
        fi
    done
    echo
    
    # Répertoires de données
    if [ "$keep_data" != "true" ]; then
        echo -e "${RED}Données à supprimer définitivement:${NC}"
        local dirs=("/opt/claude-state" "/opt/claude-projects" "/opt/claude-backups" "/opt/tmp")
        for dir in "${dirs[@]}"; do
            if [ -d "$dir" ]; then
                local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "N/A")
                local files=$(find "$dir" -type f 2>/dev/null | wc -l || echo "0")
                echo "  ✗ $dir ($size, $files fichiers)"
            fi
        done
        echo
        warning "ATTENTION: Toutes vos versions et backups seront perdus !"
        echo
    else
        echo -e "${GREEN}Données conservées:${NC}"
        echo "  ✓ /opt/claude-state (versions et métadonnées)"
        echo "  ✓ /opt/claude-projects (projets IaC générés)"
        echo "  ✓ /opt/claude-backups (snapshots et sauvegardes)"
        echo
    fi
    
    # Configuration
    if [ "$keep_config" != "true" ]; then
        echo -e "${YELLOW}Configuration à nettoyer:${NC}"
        echo "  ✗ Alias dans ~/.bashrc (cv, cr, claude-help, claude-run)"
        echo "  ✗ PATH modification dans ~/.bashrc"
        echo
    else
        echo -e "${GREEN}Configuration conservée:${NC}"
        echo "  ✓ Alias dans ~/.bashrc"
        echo "  ✓ PATH dans ~/.bashrc"
        echo
    fi
    
    if [ "$dry_run" = "true" ]; then
        echo -e "${PURPLE}[DRY-RUN] Aucune suppression ne sera effectuée${NC}"
    fi
}

# Créer une sauvegarde des données
create_backup() {
    local backup_dir="$HOME/claude-iac-backup-$(date +%Y%m%d_%H%M%S)"
    
    log "Création d'une sauvegarde dans $backup_dir..."
    
    mkdir -p "$backup_dir"
    
    # Sauvegarder les scripts
    if [ -d "$HOME/bin" ]; then
        mkdir -p "$backup_dir/bin"
        cp "$HOME/bin/claude-"* "$backup_dir/bin/" 2>/dev/null || true
    fi
    
    # Sauvegarder les données
    local dirs=("/opt/claude-state" "/opt/claude-projects" "/opt/claude-backups")
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            cp -r "$dir" "$backup_dir/" 2>/dev/null || true
        fi
    done
    
    # Sauvegarder la configuration
    if [ -f "$HOME/.bashrc" ]; then
        grep -A 10 -B 2 "Claude IaC" "$HOME/.bashrc" > "$backup_dir/bashrc_claude_config.txt" 2>/dev/null || true
    fi
    
    # Créer un script de restauration
    cat > "$backup_dir/restore.sh" << 'RESTORE_EOF'
#!/bin/bash
# Script de restauration Claude IaC
# Généré le $(date)

echo "=== Restauration Claude IaC ==="

# Restaurer les scripts
if [ -d "bin" ]; then
    echo "Restauration des scripts..."
    mkdir -p "$HOME/bin"
    cp bin/* "$HOME/bin/"
    chmod +x "$HOME/bin/claude-"*
fi

# Restaurer les données
for dir in claude-state claude-projects claude-backups; do
    if [ -d "$dir" ]; then
        echo "Restauration de /opt/$dir..."
        sudo mkdir -p "/opt/$dir"
        sudo cp -r "$dir"/* "/opt/$dir/"
        sudo chown -R $USER:$USER "/opt/$dir"
    fi
done

# Restaurer la configuration
if [ -f "bashrc_claude_config.txt" ]; then
    echo "Configuration à ajouter manuellement à ~/.bashrc:"
    cat bashrc_claude_config.txt
fi

echo "Restauration terminée. Relancez votre terminal."
RESTORE_EOF
    chmod +x "$backup_dir/restore.sh"
    
    # Créer un README
    cat > "$backup_dir/README.md" << README_EOF
# Sauvegarde Claude IaC

Sauvegarde créée le: $(date)
Utilisateur: $(whoami)
Hostname: $(hostname)

## Contenu sauvegardé

- \`bin/\`: Scripts Claude IaC
- \`claude-state/\`: Base de données des versions
- \`claude-projects/\`: Projets IaC générés
- \`claude-backups/\`: Snapshots et sauvegardes
- \`bashrc_claude_config.txt\`: Configuration bash
- \`restore.sh\`: Script de restauration automatique

## Restauration

Pour restaurer l'installation:
\`\`\`bash
cd $(basename $backup_dir)
chmod +x restore.sh
./restore.sh
\`\`\`

Ou manuellement:
1. Copier les scripts de \`bin/\` vers \`~/bin/\`
2. Restaurer les répertoires vers \`/opt/\`
3. Ajouter la configuration à \`~/.bashrc\`
README_EOF
    
    success "Sauvegarde créée: $backup_dir"
    echo "  Script de restauration: $backup_dir/restore.sh"
    echo
}

# Supprimer les scripts
remove_scripts() {
    local dry_run="$1"
    
    log "Suppression des scripts Claude IaC..."
    
    local scripts=("claude-iac" "claude-versions" "claude-rollback" "claude-help")
    local removed_count=0
    
    for script in "${scripts[@]}"; do
        if [ -f "$HOME/bin/$script" ]; then
            if [ "$dry_run" != "true" ]; then
                rm -f "$HOME/bin/$script"
            fi
            success "✓ Supprimé: $HOME/bin/$script"
            ((removed_count++))
        fi
    done
    
    if [ $removed_count -eq 0 ]; then
        warning "Aucun script Claude IaC trouvé dans $HOME/bin/"
    else
        success "$removed_count scripts supprimés"
    fi
    
    # Supprimer le répertoire ~/bin s'il est vide
    if [ "$dry_run" != "true" ] && [ -d "$HOME/bin" ]; then
        if [ -z "$(ls -A "$HOME/bin" 2>/dev/null)" ]; then
            rmdir "$HOME/bin" 2>/dev/null || true
            log "Répertoire ~/bin supprimé (vide)"
        fi
    fi
}

# Supprimer les données
remove_data() {
    local dry_run="$1"
    
    log "Suppression des données Claude IaC..."
    
    local dirs=("/opt/claude-state" "/opt/claude-projects" "/opt/claude-backups" "/opt/tmp")
    local removed_count=0
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            if [ "$dry_run" != "true" ]; then
                # Vérifier les permissions avant suppression
                if [ -w "$dir" ]; then
                    rm -rf "$dir"
                else
                    sudo rm -rf "$dir"
                fi
            fi
            success "✓ Supprimé: $dir"
            ((removed_count++))
        fi
    done
    
    if [ $removed_count -eq 0 ]; then
        warning "Aucune donnée Claude IaC trouvée dans /opt/"
    else
        success "$removed_count répertoires supprimés"
    fi
}

# Nettoyer la configuration
clean_config() {
    local dry_run="$1"
    
    log "Nettoyage de la configuration..."
    
    if [ ! -f "$HOME/.bashrc" ]; then
        warning "Fichier ~/.bashrc non trouvé"
        return
    fi
    
    # Créer un backup de .bashrc
    if [ "$dry_run" != "true" ]; then
        cp "$HOME/.bashrc" "$HOME/.bashrc.backup.$(date +%Y%m%d_%H%M%S)"
        log "Backup de ~/.bashrc créé"
    fi
    
    # Supprimer les alias et la configuration PATH
    if [ "$dry_run" != "true" ]; then
        # Supprimer les lignes spécifiques à Claude IaC
        sed -i '/# Alias Claude IaC/,/^$/d' "$HOME/.bashrc" 2>/dev/null || true
        sed -i '/export PATH=.*\/bin:$PATH/d' "$HOME/.bashrc" 2>/dev/null || true
        
        # Supprimer les alias individuels si ils existent
        sed -i '/alias claude-run=/d' "$HOME/.bashrc" 2>/dev/null || true
        sed -i '/alias cv=/d' "$HOME/.bashrc" 2>/dev/null || true
        sed -i '/alias cr=/d' "$HOME/.bashrc" 2>/dev/null || true
        sed -i '/alias claude-help=/d' "$HOME/.bashrc" 2>/dev/null || true
    fi
    
    success "✓ Configuration nettoyée dans ~/.bashrc"
    log "Un backup a été créé au cas où"
}

# Vérifier les processus en cours
check_running_processes() {
    local processes=$(ps aux | grep -E "(claude-iac|claude-versions|claude-rollback)" | grep -v grep || true)
    
    if [ -n "$processes" ]; then
        warning "Processus Claude IaC détectés en cours d'exécution:"
        echo "$processes"
        echo
        question "Voulez-vous les arrêter? (y/N)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            pkill -f "claude-iac" 2>/dev/null || true
            pkill -f "claude-versions" 2>/dev/null || true
            pkill -f "claude-rollback" 2>/dev/null || true
            success "Processus arrêtés"
        fi
    fi
}

# Validation finale
final_verification() {
    log "Vérification finale..."
    
    local issues=0
    
    # Vérifier que les scripts sont supprimés
    local scripts=("claude-iac" "claude-versions" "claude-rollback" "claude-help")
    for script in "${scripts[@]}"; do
        if [ -f "$HOME/bin/$script" ]; then
            error "✗ Script encore présent: $HOME/bin/$script"
            ((issues++))
        fi
    done
    
    # Vérifier que les répertoires sont supprimés
    local dirs=("/opt/claude-state" "/opt/claude-projects" "/opt/claude-backups")
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            error "✗ Répertoire encore présent: $dir"
            ((issues++))
        fi
    done
    
    if [ $issues -eq 0 ]; then
        success "✓ Désinstallation complète vérifiée"
    else
        warning "⚠ $issues éléments n'ont pas pu être supprimés"
    fi
}

# Afficher le résumé final
show_final_summary() {
    local kept_data="$1"
    local kept_config="$2"
    local backup_created="$3"
    
    echo
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}     DÉSINSTALLATION CLAUDE IaC TERMINÉE${NC}"
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo
    
    echo -e "${BLUE}Éléments supprimés:${NC}"
    echo "  ✓ Scripts Claude IaC (~bin/claude-*)"
    
    if [ "$kept_data" != "true" ]; then
        echo "  ✓ Base de données des versions (/opt/claude-state)"
        echo "  ✓ Projets IaC générés (/opt/claude-projects)"
        echo "  ✓ Snapshots et backups (/opt/claude-backups)"
        echo "  ✓ Répertoire temporaire (/opt/tmp)"
    fi
    
    if [ "$kept_config" != "true" ]; then
        echo "  ✓ Configuration bash (~/.bashrc)"
        echo "  ✓ Alias (cv, cr, claude-help, claude-run)"
    fi
    
    echo
    
    if [ "$kept_data" = "true" ]; then
        echo -e "${YELLOW}Données conservées:${NC}"
        echo "  • /opt/claude-state (versions et métadonnées)"
        echo "  • /opt/claude-projects (projets IaC)"
        echo "  • /opt/claude-backups (snapshots)"
        echo "  Pour les supprimer: sudo rm -rf /opt/claude-*"
        echo
    fi
    
    if [ "$kept_config" = "true" ]; then
        echo -e "${YELLOW}Configuration conservée:${NC}"
        echo "  • Alias dans ~/.bashrc"
        echo "  • PATH modification"
        echo
    fi
    
    if [ "$backup_created" = "true" ]; then
        echo -e "${GREEN}Sauvegarde disponible:${NC}"
        echo "  • Consultez ~/claude-iac-backup-* pour restaurer"
        echo
    fi
    
    echo -e "${BLUE}Actions recommandées:${NC}"
    echo "  • Redémarrez votre terminal ou exécutez: source ~/.bashrc"
    echo "  • Vérifiez que 'claude' fonctionne toujours normalement"
    if [ "$kept_data" != "true" ]; then
        echo "  • Vérifiez /opt/ pour vous assurer que tout est propre"
    fi
    echo
    
    success "Claude IaC a été désinstallé avec succès"
    log "Merci d'avoir utilisé Claude IaC System !"
}

# Fonction principale
main() {
    local keep_data=false
    local keep_config=false
    local force=false
    local backup_data=false
    local dry_run=false
    
    # Parser les arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --keep-data)
                keep_data=true
                shift
                ;;
            --keep-config)
                keep_config=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --backup-data)
                backup_data=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "Option inconnue: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}    DÉSINSTALLATION CLAUDE IaC SYSTEM${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo
    
    # Vérifications initiales
    check_installation
    check_running_processes
    
    # Afficher le résumé
    show_removal_summary "$keep_data" "$keep_config" "$dry_run"
    
    # Demander confirmation si pas en mode force
    if [ "$force" != "true" ] && [ "$dry_run" != "true" ]; then
        echo
        question "Êtes-vous sûr de vouloir continuer? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log "Désinstallation annulée par l'utilisateur"
            exit 0
        fi
    fi
    
    echo
    log "Début de la désinstallation..."
    
    # Créer une sauvegarde si demandée
    local backup_created=false
    if [ "$backup_data" = "true" ] && [ "$dry_run" != "true" ]; then
        create_backup
        backup_created=true
    fi
    
    # Supprimer les composants
    remove_scripts "$dry_run"
    
    if [ "$keep_data" != "true" ]; then
        remove_data "$dry_run"
    fi
    
    if [ "$keep_config" != "true" ]; then
        clean_config "$dry_run"
    fi
    
    # Vérification finale
    if [ "$dry_run" != "true" ]; then
        final_verification
    fi
    
    # Résumé final
    show_final_summary "$keep_data" "$keep_config" "$backup_created"
}

# Point d'entrée
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
