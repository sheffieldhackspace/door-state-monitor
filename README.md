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

# enable systemd service to run in background
sudo cp door-state-monitor.service /etc/systemd/system/door-state-monitor.service
sudo systemctl enable door-state-monitor.service
sudo systemctl start door-state-monitor.service
sudo systemctl status door-state-monitor.service
```

## `read.sh`

set this up in nginx to be a CGI script. simple metrics endpoint.

```nginx

```

Then, the Prometheus configuration should be:

```yaml

```
