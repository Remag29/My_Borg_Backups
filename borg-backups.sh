#!/usr/bin/env bash

# get current directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# load values from .env
set -o allexport
eval $(cat ${DIR}'/.env' | sed -e '/^#/d;/^\s*$/d' -e 's/\(\w*\)[ \t]*=[ \t]*\(.*\)/\1=\2/' -e "s/=['\"]\(.*\)['\"]/=\1/g" -e "s/'/'\\\''/g" -e "s/=\(.*\)/='\1'/g")
set +o allexport

# Setting this, so the repo does not need to be given on the commandline:
export BORG_REPO=${ENV_BORG_REPO}
# See the section "Passphrase notes" for more infos.
export BORG_PASSPHRASE=${ENV_BORG_PASSPHRASE}


##
## write output to log file
##

exec > >(tee -i ${LOG})
exec 2>&1


# some helpers and error handling:
info() { printf "\n%s %s\n\n" "$( date )" "$*" >&2; }
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM


##                  ##
## Start the backup ##
##                  ##

info "Starting backup"

borg create                         \
    --warning                       \
    --filter AME                    \
    --list                          \
    --stats                         \
    --show-rc                       \
    --compression lz4               \
    --exclude-caches                \
    ::'{hostname}-{now}'            \
    --patterns-from ${DIR}'/patterns.lst'

backup_exit=$?

##                   ##
## Prune and Compact ##
##                   ##

info "Pruning repository"

# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-' prefix is very important to
# limit prune's operation to this machine's archives and not apply to
# other machines' archives also:

borg prune                          \
    --list                          \
    --glob-archives '{hostname}-'   \
    --show-rc                       \
    --keep-daily    14              \
    --keep-weekly   4               \
    --keep-monthly  6               \

prune_exit=$?

# actually free repo disk space by compacting segments

info "Compacting repository"

borg compact -v

compact_exit=$?


# use highest exit code as global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
global_exit=$(( compact_exit > global_exit ? compact_exit : global_exit ))

if [ ${global_exit} -eq 0 ]; then
    info "Backup, Prune, and Compact finished successfully"
elif [ ${global_exit} -eq 1 ]; then
    info "Backup, Prune, and/or Compact finished with warnings"
else
    info "Backup, Prune, and/or Compact finished with errors"
fi

exit ${global_exit}