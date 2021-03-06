#!/bin/bash

ROOT=/root

# if [[ -n "$INPUT_DEBUG" ]]; then
#     echo "================================================"
#     echo "Version: v$(cat VERSION)"
#     echo "INPUT_REMOTE_BRANCH: $INPUT_REMOTE_BRANCH"
#     echo "INPUT_REPOSITORY: $INPUT_REPOSITORY"
#     echo "INPUT_SSH_PASSWORD: $INPUT_SSH_PASSWORD"
#     echo "INPUT_SSH_PUBLIC_KEY: $INPUT_SSH_PUBLIC_KEY"
#     echo "INPUT_SSH_PRIVATE_KEY: "
#     echo "$INPUT_SSH_PRIVATE_KEY"
#     echo "================================================"
# fi

parse_url() {
    local url=""
    URL_PROTO="$(echo "$1" | grep :// | sed -e's,^\(.*://\).*,\1,g')"
    # remove the protocol
    url="${1/$URL_PROTO/}"
    # extract the user (if any)
    URL_USERPASS="$(echo "$url" | grep @ | cut -d@ -f1)"
    URL_PASS="$(echo "$URL_USERPASS" | grep : | cut -d: -f2)"
    if [ -n "$URL_PASS" ]; then
        URL_USER="$(echo "$URL_USERPASS" | grep : | cut -d: -f1)"
    else
        URL_USER="$URL_USERPASS"
    fi

    # extract the host
    URL_HOST="$(echo "${url/$URL_USER@/}" | cut -d/ -f1)"
    # by request - try to extract the port
    URL_PORT="$(echo "$URL_HOST" | sed -e 's,^.*:,:,g' -e 's,.*:\([0-9]*\).*,\1,g' -e 's,[^0-9],,g')"
    if [ -n "$URL_PORT" ]; then
        URL_HOST="$(echo "$URL_HOST" | grep : | cut -d: -f1)"
    fi
    # extract the path (if any)
    URL_PATH="$(echo "$url" | grep / | cut -d/ -f2-)"
    
    if [[ -n "$INPUT_DEBUG" ]]; then
            echo "URL: $1"
            echo "URL_PROTO: $URL_PROTO"
            echo "URL_USER:  $URL_USER"
            echo "URL_PASS:  $URL_PASS"
            echo "URL_HOST:  URL_HOST"
            echo "URL_PORT:  $URL_PORT: "
            echo "URL_PATH:  $URL_PATH"
    fi
}

parse_url "$INPUT_REPOSITORY"
if [[ -n "$INPUT_DEBUG" ]]; then
    echo "Setting SSHPASS"
fi
export SSHPASS="$INPUT_SSH_PASSWORD"

# Create .ssh directory
if [[ ! -d "$ROOT/.ssh" ]]; then
    if [[ -n "$INPUT_DEBUG" ]]; then
        echo "creating $ROOT/.ssh"
    fi
    mkdir -p "$ROOT/.ssh"
fi

# Create KNOWN_HOSTS.
if [[ ! -f "$ROOT/.ssh/known_hosts" ]]; then
    if [[ -n "$INPUT_DEBUG" ]]; then
        echo "creating $ROOT/.ssh/known_hosts"
    fi
    touch "$ROOT/.ssh/known_hosts"
fi

if [[ -n "$URL_HOST" ]]; then
    if [[ -n "$INPUT_DEBUG" ]]; then
        echo "adding git host to known_hosts"
    fi
    if [[ -n "$URL_PORT" ]]; then
        ssh-keyscan -t rsa -p "$URL_PORT" "$URL_HOST" >> "$ROOT/.ssh/known_hosts"
    else
        ssh-keyscan -t rsa "$URL_HOST" >> "$ROOT/.ssh/known_hosts"
    fi
fi

if [[ -z "$INPUT_SSH_KNOWN_HOSTS" ]]; then
    if [[ -n "$INPUT_DEBUG" ]]; then
        echo "adding github.com to known_hosts"
    fi
    ssh-keyscan -t rsa github.com >> "$ROOT/.ssh/known_hosts"
else
    if [[ -n "$INPUT_DEBUG" ]]; then
        echo "adding user defined known_hosts"
    fi
    echo "$INPUT_SSH_KNOWN_HOSTS" >> "$ROOT/.ssh/known_hosts"
fi

# KNOWN_HOSTS debug.
if [[ -n "$INPUT_DEBUG" ]]; then
    echo "KNOWN_HOSTS FILE:"
   cat "$ROOT/.ssh/known_hosts"
fi

# SSH files.
if [[ -n "$INPUT_DEBUG" ]]; then
    echo "creating ssh key files"
fi

# echo "$INPUT_SSH_PRIVATE_KEY" > "$ROOT/.ssh/id_rsa"
printenv INPUT_SSH_PRIVATE_KEY > "$ROOT/.ssh/id_rsa"
# echo "$INPUT_SSH_PRIVATE_KEY" | tr -d '\r' > "$ROOT/.ssh/id_rsa"
chmod 600 "$ROOT/.ssh/id_rsa"
# if [[ -n "$INPUT_DEBUG" ]]; then
#     echo "PRIVATE KEY:"
#     echo "$(cat "$ROOT/.ssh/id_rsa")"
# fi

if [[ -n "$INPUT_SSH_PUBLIC_KEY" ]]; then
    printenv INPUT_SSH_PUBLIC_KEY > "$ROOT/.ssh/id_rsa.pub"
    chmod 600 "$ROOT/.ssh/id_rsa.pub"
    # if [[ -n "$INPUT_DEBUG" ]]; then
    #     echo "PUBLIC KEY:"
    #     echo "$(cat "$ROOT/.ssh/id_rsa.pub")"
    # fi
fi

# Create SSH config.
if [[ ! -f "$ROOT/.ssh/config" ]]; then
    if [[ -n "$INPUT_DEBUG" ]]; then
        echo "creating .ssh/config"
    fi
    touch "$ROOT/.ssh/config"
    echo "Host $URL_HOST
  HostName $URL_HOST
  AddKeysToAgent yes" >> "$ROOT/.ssh/config"
    
    if [[ -f "$ROOT/.ssh/id_rsa" ]]; then
        if [[ -n "$INPUT_DEBUG" ]]; then
            echo "id_rsa exists adding to config"
        fi
        echo "  IdentityFile $ROOT/.ssh/id_rsa" >> "$ROOT/.ssh/config"
    fi
    if [ -n "$URL_PORT" ]; then
        echo "  Port $URL_PORT" >> "$ROOT/.ssh/config"
    fi
    if [ -n "$URL_USER" ]; then
        echo "  User $URL_USER" >> "$ROOT/.ssh/config"
    fi

    if [[ -n "$INPUT_DEBUG" ]]; then
        cat "$ROOT/.ssh/config"
    fi

    chmod 600 "$ROOT/.ssh/config"
fi

# SSH Agent.
if [[ -n "$INPUT_DEBUG" ]]; then
    echo "starting ssh agent; adding key"
fi

function add_ssh_keys () {
  if ssh-add -l | grep -q "$1"; then
    echo "$1 key is ready"
  else
    /usr/bin/expect -c "
    spawn /usr/bin/ssh-add \"$1\";
    expect 'Enter passphrase';
    send $2\r;
    expect eof;"
  fi
}

ssh-agent -a "$SSH_AUTH_SOCK" > /dev/null
add_ssh_keys "$ROOT/.ssh/id_rsa" "$INPUT_SSH_PASSWORD"

# if [[ -n "$INPUT_DEBUG" ]]; then 
#     openssl enc -base64 <<< "$INPUT_SSH_PASSWORD"
#     openssl enc -base64 <<< "$(cat "$ROOT/.ssh/id_rsa")"
# fi

# # Add github.com to SSH config; just because.
# echo "Host github.com
#   HostName github.com
#   AddKeysToAgent yes
#   User git
#   PreferredAuthentications publickey
#   Port 22
#   IdentityFile $ROOT/.ssh/id_rsa" >> "$ROOT/.ssh/config"

# Update git settings/config.
if [[ -n "$INPUT_DEBUG" ]]; then 
    echo "updating git config"
fi
git config --global credential.helper 'cache --timeout=300'
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=$ROOT/.ssh/known_hosts"
export GIT_SSH_VARIANT="ssh"
git config core.sshCommand "ssh -o UserKnownHostsFile=$ROOT/.ssh/known_hosts"
git config --global ssh.variant "ssh"

if [[ -n "$INPUT_DEBUG" ]]; then
    echo "git refs"
    git show-ref
fi

if [[ -n "$INPUT_DEBUG" ]]; then
    echo "adding remote upstream repo"
fi
git remote add upstream "$INPUT_REPOSITORY"
git fetch --all
echo "$INPUT_SSH_PASSWORD"

# if [[ -n "$INPUT_DEBUG" ]]; then
#     echo "git config"
#     git --no-pager config -l
# fi

if [[ -n "$INPUT_DEBUG" ]]; then
    echo "getting the current branch"
fi
current_branch=${GITHUB_REF#refs/heads/}

if [[ -n "$INPUT_REMOTE_BRANCH" ]]; then
    branch="$INPUT_REMOTE_BRANCH"
else
    branch="$current_branch"
fi
if [[ -n "$INPUT_DEBUG" ]]; then
    echo "pushing current branch ($current_branch) to $branch"
    # GIT_SSH_VARIANT="sshpass -e ssh"
    # GIT_TRACE=true
    # GIT_CURL_VERBOSE=true
    # GIT_SSH_COMMAND="sshpass -e ssh -vvv -o UserKnownHostsFile=$ROOT/.ssh/known_hosts"
    # GIT_TRACE_PACK_ACCESS=true 
    # GIT_TRACE_PACKET=true 
    # GIT_TRACE_PACKFILE=true 
    # GIT_TRACE_PERFORMANCE=true 
    # GIT_TRACE_SETUP=true 
    # GIT_TRACE_SHALLOW=true
fi

if [[ -n "$branch" ]]; then
    git push -f upstream "HEAD:$branch"
else
    echo "No branch!" 1>&2
    exit 64
fi

exit
