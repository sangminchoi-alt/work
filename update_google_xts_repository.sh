pssh -H "
dev2-google01@192.168.2.201
dev2-google02@192.168.2.202
dev2-google04@192.168.2.204
dev2-google10@192.168.3.210
dev2-google11@192.168.3.211
" -i "cd ~/google_xts && git checkout -f && git clean -fd &&git pull"
