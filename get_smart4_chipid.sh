#!/bin/bash

# adb를 통해 chipid 정보 가져오기
chipid_output=$(adb shell cat /proc/cpu_chipid)

# Serial 값 추출
serial=$(echo "$chipid_output" | grep Serial | awk '{print $2}')

# 마지막 16자리 추출
last16=${serial: -16}

# 2글자씩 끊어서 배열로 저장 (바이트 단위)
bytes=()
for (( i=0; i<${#last16}; i+=2 )); do
    bytes+=("${last16:$i:2}")
done

# 배열을 역순으로 정렬
reversed=""
for (( i=${#bytes[@]}-1; i>=0; i-- )); do
    reversed+="${bytes[i]}"
done

# 결과 출력
echo "$reversed"
