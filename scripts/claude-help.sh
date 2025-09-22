#!/bin/bash
# Script d'aide rapide et utilitaires Claude IaC
# Sauvegarder comme ~/bin/claude-help
# Aide interactive

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

show_main_help() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                  CLAUDE IaC SYSTEM                        ║${NC}"
    echo -e "${CYAN}║           Versioning & Rollback pour Claude Code         ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo
    
    echo -e "${WHITE}🚀 COMMANDES PRINCIPALES${NC}"
    echo
    echo -e "${GREEN}claude-iac <commande>${NC}     - Exécuter Claude avec versioning automatique"
    echo -e "${GREEN}claude-versions${NC}           - Gérer les versions (list, show, stats, clean)"
    echo -e "${GREEN}claude-rollback <id>${NC}      - Rollback vers une version antérieure"
    echo
    
    echo -e "${WHITE}📋 ALIAS RAPIDES${NC}"
    echo
    echo -e "${YELLOW}cv${NC}                       - Alias pour claude-versions"
    echo -e "${YELLOW}cr <id>${NC}                  - Alias pour claude-rollback"
    echo
    
    echo -e "${WHITE}🔧 EXEMPLES D'UTILISATION${NC}"
    echo
    echo -e "${BLUE}# Analyser un projet avec versioning:${NC}"
    echo "claude-iac \"Analyse ce projet Python et suggère des améliorations\""
    echo
    echo -e "${BLUE}# Voir toutes les versions:${NC}"
    echo "cv list"
    echo
    echo -e "${BLUE}# Voir les détails d'une version:${NC}"
    echo "cv show v20241201_143022_1234"
    echo
    echo -e "${BLUE}# Rollback si problème:${NC}"
    echo "cr v20241201_143022_1234"
    echo
    echo -e "${BLUE}# Statistiques et nettoyage:${NC}"
    echo "cv stats"
    echo "cv clean 30  # Supprimer versions > 30 jours"
    echo
    
    echo -e "${WHITE}📁 STRUCTURE DES FICHIERS${NC}"
    echo
    echo -e "${PURPLE}/opt/claude-state/${NC}     - Base de données des versions"
    echo -e "${PURPLE}/opt/claude-projects/${NC}  - Projets IaC générés (scripts, Ansible, Terraform)"
    echo -e "${PURPLE}/opt/claude-backups/${NC}   - Snapshots et sauvegardes"
    echo -e "${PURPLE}/opt/tmp/${NC}             - Répertoire temporaire pour Claude"
    echo
    
    echo -e "${WHITE}⚡ COMMANDES AVANCÉES${NC}"
    echo
    echo -e "${CYAN}claude-help status${NC}      - État du système"
    echo -e "${CYAN}claude-help examples${NC}    - Plus d'exemples"
    echo -e "${CYAN}claude-help troubleshoot${NC} - Guide de dépannage"
    echo -e "${CYAN}claude-help workflow${NC}    - Workflow recommandé"
    echo
    
    echo -e "${WHITE}📖 DOCUMENTATION${NC}"
    echo
    echo "Documentation complète: ${YELLOW}/opt/claude-state/README.md${NC}"
    echo
    
    echo -e "${GREEN}💡 CONSEIL:${NC} Utilisez toujours ${YELLOW}claude-iac${NC} au lieu de ${YELLOW}claude${NC} pour bénéficier du versioning !"
}

show_status() {
    echo -e "${CYAN}═══ ÉTAT DU SYSTÈME CLAUDE IaC ═══${NC}"
    echo
    
    # Vérifier Claude Code
    if command -v claude &> /dev/null; then
        local claude_version=$(claude --version 2>/dev/null | head -1)
        echo -e "${GREEN}✓ Claude Code:${NC} $claude_version"
    else
        echo -e "${RED}✗ Claude Code:${NC} Non installé"
    fi
    
    # Vérifier les scripts
    local scripts=("claude-iac" "claude-versions" "claude-rollback")
    echo -e "\n${WHITE}Scripts installés:${NC}"
    for script in "${scripts[@]}"; do
        if [ -x "$HOME/bin/$script" ]; then
            echo -e "${GREEN}  ✓ $script${NC}"
        else
            echo -e "${RED}  ✗ $script${NC}"
        fi
    done
    
    # Vérifier les répertoires
    echo -e "\n${WHITE}Répertoires:${NC}"
    local dirs=("/opt/claude-state" "/opt/claude-projects" "/opt/claude-backups" "/opt/tmp")
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "N/A")
            local files=$(find "$dir" -type f 2>/dev/null | wc -l || echo "0")
            echo -e "${GREEN}  ✓ $dir${NC} (${YELLOW}$size${NC}, ${YELLOW}$files fichiers${NC})"
        else
            echo -e "${RED}  ✗ $dir${NC}"
        fi
    done
    
    # Statistiques des versions
    echo -e "\n${WHITE}Versions:${NC}"
    if [ -f "/opt/claude-state/versions.db" ]; then
        local total=$(grep -v "^#" "/opt/claude-state/versions.db" | wc -l 2>/dev/null || echo "0")
        local success=$(grep -c "|SUCCESS|" "/opt/claude-state/versions.db" 2>/dev/null || echo "0")
        local errors=$(grep -c "|ERROR|" "/opt/claude-state/versions.db" 2>/dev/null || echo "0")
        echo -e "  Total: ${YELLOW}$total${NC}"
        echo -e "  Succès: ${GREEN}$success${NC}"
        echo -e "  Erreurs: ${RED}$errors${NC}"
    else
        echo -e "  ${YELLOW}Aucune version encore créée${NC}"
    fi
    
    # Variables d'environnement
    echo -e "\n${WHITE}Configuration:${NC}"
    echo -e "  TMPDIR: ${YELLOW}${TMPDIR:-/tmp}${NC}"
    echo -e "  PATH contient ~/bin: $([[ ":$PATH:" == *":$HOME/bin:"* ]] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}")"
}

show_examples() {
    echo -e "${CYAN}═══ EXEMPLES D'UTILISATION ═══${NC}"
    echo
    
    echo -e "${WHITE}🐍 PROJETS PYTHON${NC}"
    echo -e "${BLUE}# Analyser et optimiser du code Python:${NC}"
    echo "claude-iac \"Analyse ce script Python et suggère des optimisations de performance\""
    echo
    echo -e "${BLUE}# Ajouter des tests unitaires:${NC}"
    echo "claude-iac \"Crée des tests unitaires pour toutes les fonctions de ce module Python\""
    echo
    echo -e "${BLUE}# Refactoring:${NC}"
    echo "claude-iac \"Refactorise ce code pour suivre les bonnes pratiques PEP8\""
    echo
    
    echo -e "${WHITE}🌐 DÉVELOPPEMENT WEB${NC}"
    echo -e "${BLUE}# API Flask:${NC}"
    echo "claude-iac \"Crée une API REST Flask avec authentification JWT\""
    echo
    echo -e "${BLUE}# Frontend React:${NC}"
    echo "claude-iac \"Développe un composant React pour un dashboard utilisateur\""
    echo
    
    echo -e "${WHITE}🔧 DEVOPS & INFRA${NC}"
    echo -e "${BLUE}# Docker:${NC}"
    echo "claude-iac \"Crée un Dockerfile optimisé pour cette application Node.js\""
    echo
    echo -e "${BLUE}# CI/CD:${NC}"
    echo "claude-iac \"Configure un pipeline GitHub Actions pour ce projet\""
    echo
    
    echo -e "${WHITE}📊 DATA & ML${NC}"
    echo -e "${BLUE}# Analyse de données:${NC}"
    echo "claude-iac \"Analyse ce dataset CSV et crée des visualisations avec matplotlib\""
    echo
    echo -e "${BLUE}# Machine Learning:${NC}"
    echo "claude-iac \"Implémente un modèle de classification avec scikit-learn\""
    echo
    
    echo -e "${WHITE}🔄 GESTION DES VERSIONS${NC}"
    echo -e "${BLUE}# Après une modification problématique:${NC}"
    echo "cv list                           # Voir toutes les versions"
    echo "cv show v20241201_143022_1234     # Voir les détails"
    echo "cr v20241201_143022_1234          # Rollback"
    echo
    echo -e "${BLUE}# Maintenance périodique:${NC}"
    echo "cv stats                          # Voir l'utilisation"
    echo "cv clean 30                       # Nettoyer anciennes versions"
    echo
    
    echo -e "${WHITE}📦 REPRODUCTION & DÉPLOIEMENT${NC}"
    echo -e "${BLUE}# Reproduire sur un autre serveur:${NC}"
    echo "# Via script bash:"
    echo "/opt/claude-projects/session_v*/scripts/reproduce_*.sh"
    echo
    echo "# Via Ansible:"
    echo "ansible-playbook /opt/claude-projects/session_v*/ansible/playbook_*.yml"
    echo
    echo "# Via Terraform:"
    echo "cd /opt/claude-projects/session_v*/terraform && terraform apply"
}

show_workflow() {
    echo -e "${CYAN}═══ WORKFLOW RECOMMANDÉ ═══${NC}"
    echo
    
    echo -e "${WHITE}📋 ÉTAPES TYPIQUES${NC}"
    echo
    echo -e "${YELLOW}1. Planification${NC}"
    echo "   • Définir clairement l'objectif"
    echo "   • Vérifier l'état actuel avec: cv list"
    echo "   • Nettoyer si nécessaire: cv clean"
    echo
    
    echo -e "${YELLOW}2. Exécution avec versioning${NC}"
    echo "   claude-iac \"Votre demande détaillée ici\""
    echo
    
    echo -e "${YELLOW}3. Vérification du résultat${NC}"
    echo "   • Tester le code/configuration généré"
    echo "   • Vérifier les logs: cv show <dernière_version>"
    echo
    
    echo -e "${YELLOW}4. Actions selon le résultat${NC}"
    echo
    echo -e "${GREEN}   ✅ Si OK:${NC}"
    echo "   • Continuer avec la prochaine étape"
    echo "   • Optionnel: exporter la version importante"
    echo "     cv export <version_id>"
    echo
    echo -e "${RED}   ❌ Si problème:${NC}"
    echo "   • Analyser les logs"
    echo "   • Rollback si nécessaire: cr <version_id>"
    echo "   • Reessayer avec une demande modifiée"
    echo
    
    echo -e "${YELLOW}5. Documentation et reproduction${NC}"
    echo "   • Les scripts IaC sont générés automatiquement"
    echo "   • Utiliser pour déploiement sur d'autres environnements"
    echo "   • Archiver les versions importantes"
    echo
    
    echo -e "${WHITE}🎯 BONNES PRATIQUES${NC}"
    echo
    echo -e "${GREEN}✓ Faire:${NC}"
    echo "  • Toujours utiliser claude-iac au lieu de claude"
    echo "  • Vérifier cv stats régulièrement"
    echo "  • Nettoyer les anciennes versions périodiquement"
    echo "  • Tester avant de considérer comme final"
    echo "  • Garder des descriptions claires dans les demandes"
    echo
    echo -e "${RED}✗ Éviter:${NC}"
    echo "  • Utiliser claude directement (pas de versioning)"
    echo "  • Laisser s'accumuler trop de versions"
    echo "  • Faire des rollbacks sans comprendre le problème"
    echo "  • Ignorer les erreurs d'intégrité des backups"
    echo
    
    echo -e "${WHITE}⚡ EXEMPLE COMPLET${NC}"
    echo
    echo -e "${BLUE}# Projet: Optimiser une API Python${NC}"
    echo "cd /mon/projet/api"
    echo "claude-iac \"Analyse cette API Python et améliore les performances\""
    echo "# ... vérifier le résultat ..."
    echo "claude-iac \"Ajoute des tests de performance pour valider les améliorations\""
    echo "# ... tester ..."
    echo "cv list  # Voir les deux versions créées"
    echo "# Si la deuxième version pose problème:"
    echo "cr v20241201_143545_5678  # Rollback vers la première"
}

show_troubleshoot() {
    echo -e "${CYAN}═══ GUIDE DE DÉPANNAGE ═══${NC}"
    echo
    
    echo -e "${WHITE}🚨 PROBLÈMES COURANTS${NC}"
    echo
    
    echo -e "${YELLOW}1. \"claude-iac: command not found\"${NC}"
    echo -e "${BLUE}Cause:${NC} Script non installé ou PATH incorrect"
    echo -e "${BLUE}Solution:${NC}"
    echo "  source ~/.bashrc"
    echo "  echo \$PATH | grep ~/bin"
    echo "  ls -la ~/bin/claude-*"
    echo
    
    echo -e "${YELLOW}2. \"Permission denied\" sur /opt/${NC}"
    echo -e "${BLUE}Cause:${NC} Permissions insuffisantes"
    echo -e "${BLUE}Solution:${NC}"
    echo "  sudo chown $USER:$USER /opt/claude-*"
    echo "  chmod 755 /opt/claude-*"
    echo
    
    echo -e "${YELLOW}3. \"Backup non trouvé\" lors du rollback${NC}"
    echo -e "${BLUE}Cause:${NC} Backup supprimé ou corrompu"
    echo -e "${BLUE}Solution:${NC}"
    echo "  cv list  # Vérifier versions disponibles"
    echo "  ls -la /opt/claude-backups/"
    echo "  # Utiliser une version antérieure"
    echo
    
    echo -e "${YELLOW}4. \"Intégrité compromise\"${NC}"
    echo -e "${BLUE}Cause:${NC} Checksums ne correspondent pas"
    echo -e "${BLUE}Solution:${NC}"
    echo "  cd /opt/claude-backups/snapshot_<version>"
    echo "  md5sum -c .claude_checksums"
    echo "  # Utiliser --force en dernier recours"
    echo
    
    echo -e "${YELLOW}5. Espace disque insuffisant${NC}"
    echo -e "${BLUE}Cause:${NC} Trop de versions/backups"
    echo -e "${BLUE}Solution:${NC}"
    echo "  cv stats"
    echo "  du -sh /opt/claude-*"
    echo "  cv clean 15  # Nettoyer plus agressivement"
    echo
    
    echo -e "${WHITE}🔧 COMMANDES DE DIAGNOSTIC${NC}"
    echo
    echo -e "${GREEN}claude-help status${NC}        # État complet du système"
    echo -e "${GREEN}cv stats${NC}                  # Statistiques d'utilisation"
    echo -e "${GREEN}ls -la ~/bin/claude-*${NC}     # Vérifier les scripts"
    echo -e "${GREEN}ps aux | grep claude${NC}      # Processus Claude en cours"
    echo -e "${GREEN}tail /opt/claude-projects/session_*/logs/*.log${NC}  # Derniers logs"
    echo
    
    echo -e "${WHITE}🛠️ RÉPARATION D'URGENCE${NC}"
    echo
    echo -e "${BLUE}Recréer la base de données:${NC}"
    echo "  cp /opt/claude-state/versions.db /tmp/backup.db"
    echo "  echo '# Claude IaC Versions Database' > /opt/claude-state/versions.db"
    echo
    echo -e "${BLUE}Recréer les répertoires:${NC}"
    echo "  sudo mkdir -p /opt/{claude-state,claude-projects,claude-backups,tmp}"
    echo "  sudo chown $USER:$USER /opt/claude-*"
    echo
    echo -e "${BLUE}Réinstaller complètement:${NC}"
    echo "  # Sauvegarder les données importantes"
    echo "  tar -czf ~/claude-backup-\$(date +%Y%m%d).tar.gz /opt/claude-*"
    echo "  # Réexécuter le script d'installation"
    echo
    
    echo -e "${WHITE}📞 SUPPORT${NC}"
    echo
    echo "Si les problèmes persistent:"
    echo "• Consulter les logs détaillés dans /opt/claude-projects/*/logs/"
    echo "• Vérifier la documentation: /opt/claude-state/README.md"
    echo "• Sauvegarder les données importantes avant toute réparation"
}

# Menu interactif
show_interactive_menu() {
    while true; do
        echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║           CLAUDE IaC HELP             ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
        echo
        echo -e "${WHITE}Choisissez une option:${NC}"
        echo
        echo -e "${YELLOW}1)${NC} Aide générale"
        echo -e "${YELLOW}2)${NC} État du système"  
        echo -e "${YELLOW}3)${NC} Exemples d'utilisation"
        echo -e "${YELLOW}4)${NC} Workflow recommandé"
        echo -e "${YELLOW}5)${NC} Guide de dépannage"
        echo -e "${YELLOW}6)${NC} Lancer claude-versions"
        echo -e "${YELLOW}q)${NC} Quitter"
        echo
        read -p "Votre choix: " choice
        echo
        
        case $choice in
            1) show_main_help; echo; read -p "Appuyez sur Entrée pour continuer..." ;;
            2) show_status; echo; read -p "Appuyez sur Entrée pour continuer..." ;;
            3) show_examples; echo; read -p "Appuyez sur Entrée pour continuer..." ;;
            4) show_workflow; echo; read -p "Appuyez sur Entrée pour continuer..." ;;
            5) show_troubleshoot; echo; read -p "Appuyez sur Entrée pour continuer..." ;;
            6) claude-versions; echo; read -p "Appuyez sur Entrée pour continuer..." ;;
            q|Q) echo "Au revoir !"; break ;;
            *) echo -e "${RED}Option invalide${NC}"; sleep 1 ;;
        esac
        clear
    done
}

# Script principal
case "${1:-help}" in
    "help"|"")
        show_main_help
        ;;
    "status")
        show_status
        ;;
    "examples")
        show_examples
        ;;
    "workflow")
        show_workflow
        ;;
    "troubleshoot")
        show_troubleshoot
        ;;
    "interactive"|"menu")
        show_interactive_menu
        ;;
    *)
        echo -e "${RED}Option inconnue: $1${NC}"
        echo
        echo "Options disponibles:"
        echo "  help (défaut)    - Aide générale"
        echo "  status           - État du système"
        echo "  examples         - Exemples d'utilisation"
        echo "  workflow         - Workflow recommandé"
        echo "  troubleshoot     - Guide de dépannage"
        echo "  interactive      - Menu interactif"
        ;;
esac
