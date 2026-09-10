# Zotify helper image — https://github.com/Googolplexed0/zotify
# Upstream Dockerfile expects requirements.txt; install via pip from git instead.
FROM python:3.12-alpine

RUN apk add --no-cache ffmpeg git gcc musl-dev libffi-dev jpeg-dev zlib-dev

RUN pip install --no-cache-dir \
      "git+https://github.com/Googolplexed0/zotify.git"

WORKDIR /root
EXPOSE 4381

# Stay up so `docker exec -it … zotify …` works; OAuth listens on 4381 when logging in.
CMD ["sleep", "infinity"]
