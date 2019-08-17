FROM	debian:latest

ENV	DEBIAN_FRONTEND "noninteractive"

RUN	apt-get update && \
	apt-get install -y --no-install-recommends \
		cpio \
		moreutils \
		mtools \
		wget \
		xorriso && \
	mkdir /data

COPY	. /var/app

ENTRYPOINT ["/var/app/mkiso.sh"]
