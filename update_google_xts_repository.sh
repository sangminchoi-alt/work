pssh -H "
dev2-google01@100.125.140.37
dev2-google02@100.88.166.46
dev2-google04@100.79.228.13
dev2-google10@100.66.200.11
dev2-google11@100.105.46.6
" -i "cd ~/google_xts && git checkout -f && git clean -fd &&git pull"
