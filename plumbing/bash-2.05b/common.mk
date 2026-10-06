# SPDX-FileCopyrightText: 2021 Paul Dersey <pdersey@gmail.com>
# SPDX-FileCopyrightText: 2021 Samuel Tyler <samuel@samuelt.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

CC      = $(TOP)/../../../seed-cc/seed-cc
LD      = $(CC)
AR      = $(TOP)/../../../seed-cc/seed-ar

COMMON_CFLAGS  = \
	-DHAVE_CONFIG_H

BUILTINS_DEF_FILES = alias bind break builtin cd colon command declare \
	echo enable eval exec exit fc fg_bg hash history jobs kill let read return \
	set setattr shift source suspend test times trap type ulimit umask wait \
	getopts pushd shopt printf
