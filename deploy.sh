#!/bin/bash -e

# set version and repository before deployment
export version=1.0.0
export repository=mwaeckerlin

# run tests
docker-compose up --build --remove-orphans --detach
sleep 5s
./test.sh
docker-compose rm -vfs

# tag repository -> don't forget to run: git push --tags
git tag v$version

# build and push all variants
for tag in latest $version; do
    export tag
    docker-compose build
    docker-compose push
done

# deploy to kubernetes - or change the line to deploy elsewhere
#kubectl set image deployment/bind bind=$registry/bind:$version