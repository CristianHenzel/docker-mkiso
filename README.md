# docker_mkiso

Create Debian ISO for fully automated installations.

## Usage:
```
docker run -it --rm -v /data:/data \
	-e MKISO_ADD_PACKAGES="cifs-utils ctop curl docker.io docker-compose git htop make nano openssh-server python3-pip wget" \
	-e MKISO_COUNTRYCODE="ro" \
	-e MKISO_ROOT_PASSWORD="root" \
	-e MKISO_TIMEZONE="Europe\/Bucharest" \
	ghcr.io/cristianhenzel/docker-mkiso:latest
```

## TODO:
	- Default values for all env variables
	- Replace more of the fixed values with variables

## Hint:

Proxmox needs Display set to 'VirtIO-GPU' to work.
