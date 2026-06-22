termux-setup-storage
lw
ls
pkg update && pkg upgrade -y
nano auto_audit.sh
chmod +x auto_audit.sh
./auto_audit.sh
# Entre no diretório onde está o script
cd ~
# Crie o diretório do projeto
mkdir auto-audit-ai
cp auto_audit.sh auto-audit-ai/
# Acesse o diretório
cd auto-audit-ai
# Crie o README.md (use nano ou outro editor)
nano README.md
# Inicialize o Git
git init
git add .
git commit -m "Primeiro commit: Auto Audit AI v7.1"
# Conecte ao repositório remoto (substitua SEU_USUARIO e NOME_REPO)
git remote add origin https://github.com/SEU_USUARIO/auto-audit-ai.git
# Envie
git branch -M main
git push -u origin main
exit
