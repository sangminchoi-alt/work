pssh -H "
dev2-google01@192.168.201.201
dev2-google02@192.168.201.202
dev2-google04@192.168.201.204
dev2-google10@192.168.201.205
dev2-google11@192.168.201.206
" -i "cd ~/google_xts && git checkout -f && git clean -fd &&git pull"
