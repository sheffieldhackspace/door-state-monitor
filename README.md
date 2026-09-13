# Door state monitor

- Monitor MQTT state and save door events and fob events to files.
- Serve a `/metrics` file for Prometheus

## `listen.sh`

`listen.sh` listens to MQTT, to set up:

```bash
# set up topics using `.env`
cp .env.example .env

# ssh key for git interaction
mkdir -p /usr/shhm/.ssh/
ssh-keygen -f /usr/shhm/.ssh/doorstate-deploy-key
export GIT_SSH_COMMAND="ssh -i /usr/shhm/.ssh/doorstate-deploy-key"

# clone
git clone … /usr/shhm/doorstate
cd /usr/shhm/doorstate

# run listen (daemon, CTRL+C at some point)
./listen.sh
# check it's working (cat files)
while true; do
  for file in state/*; do
    echo "${file}"; cat "${file}" | sed 's+^+  +'; echo ""
  done; sleep 1; clear
done

# enable systemd service to run in background
sudo cp door-state-monitor.service /etc/systemd/system/door-state-monitor.service
sudo systemctl enable door-state-monitor.service
sudo systemctl start door-state-monitor.service
sudo systemctl status door-state-monitor.service

# allow system user to write status files
sudo chown -R mqttlistener:mqttlistener state
sudo chmod g+w state
sudo usermod -aG mqttlistener "${USER}"
```

## `read.sh`

set this up in nginx to be a CGI script. simple metrics endpoint.

add this as an nginx server block (i.e., a file in `/etc/nginx/sites-available/`)

```nginx
server {
    listen 8481;
    server_name _;
    location / {
        add_header "Content-type" "text/plain";
        return 200 "see /metrics";
    }
    location = /metrics {
        root /usr/shhm/doorstate;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME /usr/shhm/doorstate/read.sh;
        fastcgi_pass unix:/var/run/fcgiwrap.socket;
    }
}
```

Then, the Prometheus configuration should be:

```yaml
scrape_configs:
  - job_name: "door state metrics"
    scrape_interval: 300s
    static_configs:
      - targets: ['localhost:8481']
```
