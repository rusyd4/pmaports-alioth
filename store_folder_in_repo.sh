#!/bin/sh


rm -rf /home/agata/pmaports-alioth/device-xiaomi-alioth /home/agata/pmaports-alioth/firmware-xiaomi-alioth /home/agata/pmaports-alioth/linux-postmarketos-qcom-sm8250-alioth

cp -r ~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/linux-postmarketos-qcom-sm8250-alioth /home/agata/pmaports-alioth/linux-postmarketos-qcom-sm8250-alioth
cp -r ~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/device-xiaomi-alioth /home/agata/pmaports-alioth/device-xiaomi-alioth
cp -r ~/.local/var/pmbootstrap/cache_git/pmaports/device/testing/firmware-xiaomi-alioth /home/agata/pmaports-alioth/firmware-xiaomi-alioth

echo "Folders replaced in the repo"
