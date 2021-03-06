# Copyright © 2018, Octave Online LLC
#
# This file is part of Octave Online Server.
#
# Octave Online Server is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# Octave Online Server is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public
# License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Octave Online Server.  If not, see
# <https://www.gnu.org/licenses/>.

SHELL := /bin/bash
NODE = node

# Read options from config file
get_config = ${shell $(NODE) -e "console.log(require('./shared').config.$(1))"}
GIT_HOST      = $(call get_config,git.hostname)
GIT_DIR       = $(call get_config,docker.gitdir)
WORK_DIR      = $(call get_config,docker.cwd)
OCTAVE_SUFFIX = $(call get_config,docker.images.octaveSuffix)
FILES_SUFFIX  = $(call get_config,docker.images.filesystemSuffix)
JSON_MAX_LEN  = $(call get_config,session.jsonMaxMessageLength)
CGROUP_NAME   = $(call get_config,selinux.cgroup.name)
CPU_SHARES    = $(call get_config,selinux.cgroup.cpuShares)
CPU_QUOTA     = $(call get_config,selinux.cgroup.cpuQuota)
CGROUP_UID    = $(call get_config,selinux.cgroup.uid)
CGROUP_GID    = $(call get_config,selinux.cgroup.gid)


docker-octave:
	if [[ -e bundle ]]; then rm -rf bundle; fi
	mkdir bundle
	cat dockerfiles/base.dockerfile \
		>> bundle/Dockerfile
	cat dockerfiles/build-octave.dockerfile \
		>> bundle/Dockerfile
	cat dockerfiles/entrypoint-octave.dockerfile \
		| sed -e "s;%JSON_MAX_LEN%;$(JSON_MAX_LEN);g" \
		>> bundle/Dockerfile
	cp -rL back-octave/* bundle
	docker build -t oo/$(OCTAVE_SUFFIX) bundle
	rm -rf bundle

docker-files:
	if [[ -e bundle ]]; then rm -rf bundle; fi
	mkdir bundle
	cat dockerfiles/base.dockerfile \
		>> bundle/Dockerfile
	cat dockerfiles/install-node.dockerfile \
		>> bundle/Dockerfile
	cat dockerfiles/filesystem.dockerfile \
		| sed -e "s;%GIT_DIR%;$(GIT_DIR);g" \
		| sed -e "s;%GIT_HOST%;$(GIT_HOST);g" \
		>> bundle/Dockerfile
	cat dockerfiles/entrypoint-filesystem.dockerfile \
		| sed -e "s;%GIT_DIR%;$(GIT_DIR);g" \
		| sed -e "s;%WORK_DIR%;$(WORK_DIR);g" \
		>> bundle/Dockerfile
	cp -rL back-filesystem bundle
	docker build -t oo/$(FILES_SUFFIX) bundle
	rm -rf bundle

docker-master-docker:
	echo "This image would require using docker-in-docker.  A pull request is welcome."

docker-master-selinux:
	echo "It is not currently possible to install SELinux inside of a Docker container."

install-cgroup:
	systemctl enable cgconfig
	echo "group $(CGROUP_NAME) {" >> /etc/cgconfig.conf
	echo "  perm {" >> /etc/cgconfig.conf
	echo "    admin {" >> /etc/cgconfig.conf
	echo "      uid = root;" >> /etc/cgconfig.conf
	echo "      gid = root;" >> /etc/cgconfig.conf
	echo "    }" >> /etc/cgconfig.conf
	echo "    task {" >> /etc/cgconfig.conf
	echo "      uid = $(CGROUP_UID);" >> /etc/cgconfig.conf
	echo "      gid = $(CGROUP_GID);" >> /etc/cgconfig.conf
	echo "    }" >> /etc/cgconfig.conf
	echo "  }" >> /etc/cgconfig.conf
	echo "  cpu {" >> /etc/cgconfig.conf
	echo "    cpu.shares = $(CPU_SHARES);" >> /etc/cgconfig.conf
	echo "    cpu.cfs_period_us = 1000000;" >> /etc/cgconfig.conf
	echo "    cpu.cfs_quota_us = $(CPU_QUOTA);" >> /etc/cgconfig.conf
	echo "  }" >> /etc/cgconfig.conf
	echo "}" >> /etc/cgconfig.conf

install-selinux-policy:
	# yum install -y selinux-policy-devel policycoreutils-sandbox selinux-policy-sandbox
	cd entrypoint/policy && make -f /usr/share/selinux/devel/Makefile octave_online.pp
	semodule -i entrypoint/policy/octave_online.pp
	restorecon -R -v /usr/local/lib/octave
	restorecon -R -v /tmp
	setenforce enforcing
	echo "For maximum security, make sure to put SELinux in enforcing mode by default in /etc/selinux/config."

install-selinux-bin:
	cp entrypoint/back-selinux.js /usr/local/bin/oo-back-selinux
	cp entrypoint/oo.service /usr/lib/systemd/system/oo.service
	cp entrypoint/oo-install-host.service /usr/lib/systemd/system/oo-install-host.service
	systemctl daemon-reload
	systemctl enable oo
	systemctl enable oo-install-host
	ln -sf $$PWD /usr/local/share/oo

install-utils-auth:
	cp entrypoint/oo_utils_auth.service /usr/lib/systemd/system/oo_utils_auth.service
	systemctl daemon-reload
	systemctl enable oo_utils_auth
	ln -sf $$PWD /usr/local/share/oo

install-site-m:
	cp back-octave/octaverc.m /usr/local/share/octave/site/m/startup/octaverc

docker: docker-octave docker-files

lint:
	cd back-filesystem && npm run lint
	cd back-master && npm run lint
	cd shared && npm run lint
	cd utils-auth && npm run lint

clean:
	if [[ -e bundle ]]; then rm -rf bundle; fi
