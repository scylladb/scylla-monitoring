#!/usr/bin/bash
print_usage() {
    echo "add_centos_user.sh [--os centos/ubuntu] [--copy]"
    exit 1
}
OS="centos"
COPY=""
while [ $# -gt 0 ]; do
    case "$1" in
        "--os")
            OS="$2"
            shift 2
            ;;
        "--copy")
            COPY="1"
            shift 1
            ;;
        *)
            print_usage
            ;;
    esac
done

if [ "$OS" = "ubuntu" ]; then
    sudo useradd -m -s $(which bash) -G sudo -G docker centos
    echo "centos ALL=(ALL) NOPASSWD:ALL" |sudo tee -a  /etc/sudoers.d/100-cloud-cntos-user > /dev/null
    if [ "$COPY" = "1" ]; then
        sudo cp -r  /home/ubuntu/scylla-grafana-monitoring-scylla-monitoring /home/centos/
    fi
    sudo chown -R centos:centos /home/centos
fi
