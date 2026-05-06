
version: '3'

services:
  specs-alert:
    build: .
    ports:
      - "5000:5000"
    restart: unless-stopped
