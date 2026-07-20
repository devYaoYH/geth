# On-demand app lifecycle controller.
# Needs docker CLI + compose plugin for compose operations via the socket.
FROM python:3.12-slim

RUN apt-get update && apt-get install -y docker.io && rm -rf /var/lib/apt/lists/*

COPY app.py /srv/launcher.py

EXPOSE 8081
USER nobody

CMD ["python3", "/srv/launcher.py"]