desc="Promote a release version for a given channel"

declare channel=""
declare platform=""
declare arch=""
declare version=""
declare STAGE_GIT=""

function usage () {
cat << EOF
usage: site.sh promote <channel> <platform> <architecture> <version>

  channel is either 'beta' or 'stable'
  platform is one of 'tizen' or 'android'
  arch is either 'x86' or 'arm'
  version is of the form A.B.C.D
  
  This script will perform the following:
  
  1. Determine the version of the website active on the live server (eg. live-20131202)
  2. Checkout that channel locally to tmp-live-20131202
  3. Commit that change to live-20131202
  4. Push that branch to GitHub
  5. Optionally activate the branch on the staging server via
     
    site.sh push live-20131202
    
  6. Remove tmp-live-20131202
  7. Change versions.js in the active tree
  8. Commit the versions.js change in the active branch

  At this point, the staging server should be tested to ensure the version update
  works as appropriate. Once satisfied, run:
    
    site.sh push live
    
  To push the version from the staging server to the live server.

EOF
}

function query_diff () {
    branch="$1"

    while true; do 
        git diff --exit-code ${branch} -- versions.js &&
            echo "No diferences."
        echo -n "Is the above diff correct? [Yn] "
        read answer
        case $answer in
        ""|Y|y)
            true
            return
            ;;
        N|n)
            cat << EOF
            
Exiting. You will need to manually edit 'versions.js'. When done, re-run:

    ${cmd} promote --manual-edit
    
And anser Yes to 'Use current version?' prompt.

EOF
            false
            return
            ;;
        esac
    done
}    

function update_version_string () {
    pattern="s,(${channel}:.*?${platform}:.*?${arch}: \")[^\"]*,\${1}${version},s"     
    cat << EOF | perl -077 -pe "${pattern}" > versions.js
/*
 * THIS FILE IS GENERATED BY scripts/promote.sh
 *
 * DO NOT MODIFY
 *
 * This file is used to dynamically update the content 
 * shown on the main site, including the home page and any 
 * content loaded from documentation/, contribute/, and wiki/.
 *
 * To see which pages from the main site are using this replacement:
 
    grep -ricE '[^!]\\${xwalk-[^-]+-[^-]+-[^-]+}' * | grep -v '0\$'
   
 *
 * Script injection occurs in xwalk.js replace_version_string
 *
 * The following pattern is replaced:
 *
 * \${XWALK-<CHANNEL>-<PLATFORM>-<ARCH>}
 *
 * To prevent replacement (eg., for a wiki page documenting
 * this process, prefix the \${XWALK...} with an exclamation (!)
 *
 * For example:
 *
 *   crosswalk-\${XWALK-BETA-ANDROID-X86}.zip 
 *   crosswalk-!\${XWALK-BETA-ANDROID-X86}.zip 
 *
 * would result in:
 *
 *   crosswalk-2.31.27.0.zip
 *   crosswalk-\${XWALK-BETA-ANDROID-X86}.zip 
 *
 * See './site.sh promote' for a script to update this file
 * and push it to the website without pushing an entirely new
 * website (eg., without needing to run './site.sh mklive').
 *
 */
var versions = {
    stable: { 
        android: {
            x86: "1.29.4.7", 
            arm: "0.0.0.0"
        },
        tizen: {
            x86: "1.29.4.7", 
            arm: "0.0.0.0"
        },
    },
    beta: {
        android: {
            x86: "2.31.27.0", 
            arm: "0.0.0.0"
        },
        tizen: {
            x86: "2.31.27.0", 
            arm: "0.0.0.0"
        },
    }
};
EOF
}


# usage: site.sh promote <channel> <platform> <architecture> <version>
function run () {
    if [[ "$1" == "-n" ]]; then
        dry_run="echo "
        shift
    else
        dry_run=""
    fi
    channel="$1"
    platform="$2"
    arch="$3"
    version="$4"
    
    if [[ "${channel}" == "" || 
          "${platform}" == "" || 
          "${arch}" == "" || 
          "${version}" == "" ]]; then
          usage
          false
          return
    fi

    echo -n "Fetching staging branch name from stg.crosswalk-project.org..." >&2
    live=$(get_remote_live_name live)
    echo "done"

    git show-ref --verify --quiet refs/heads/${live} || {
        echo -n "Fetching ${live} from GitHub..."
        git fetch origin ${live}:${live} || die "Failed."
        echo "done"
    }

    ${dry_run} git stash

    update_version_string ||
        die "Unable to set versions.js appropriately."

    query_diff HEAD -- versions.js || {
        git diff HEAD -- versions.js | patch -p1 -R || 
            die "Unable to reset to previous state. 'git stash' still active."
        git stash pop || die "git pop failed"
        false
        return
    }
    
    git commit -s -m \
        "Automatic commit with bump of ${channel} to ${version} for ${platform}-${arch}" \
        -- versions.js

    echo "Switching to ${live}..."
    git checkout ${live}
    echo "Applying versions.js from master..."
    git checkout master -- versions.js
    query_diff ${live} -- versions.js
    echo "Committing to versions.js to ${live}..."
    git commit -s -m \
        "Automatic commit with bump of ${channel} to ${version} for ${platform}-${arch}" \
        -- versions.js
    echo "Restoring GIT tree to original state"
    git stash apply
    
return

    url=$(git remote show -n origin | sed -ne 's,^.*Push.*URL: \(.*\)$,\1,p')
    
    branch=$(branchname ${rev})
    echo -en "Checking for ${branch} at ${url}..."
    git remote show origin | grep -q ${branch} || {
        echo "not found."
        echo "Running: git push -u origin ${branch}:${branch}..."
        git push -u origin ${branch}:${branch}
    }
    echo "done."

    push "set" $target $rev $current
}
