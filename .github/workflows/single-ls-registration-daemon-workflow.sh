name: single-ls-registration-daemon-workflow

on: 
  push:
    branches:
      - github-workflow
jobs:

  build-ls-registration-daemon:

     runs-on: ubuntu-latest

     steps:


       # TOdo:  branch is hardcoded 
       # make sure it is ok to update
        - name: Check out Repo
          uses: actions/checkout@v4
          with:
           ref: 5.2.0

        - name: Fetch workflow script from projects
          env:
             github-token: ${{ secrets.GIT_ACTIONS }}
          run: |
            git clone https://github.com/cs1867/project.git project
            case "${{ env.BUILD_OS }}" in
              'ol8'|'el9')
                 cp project/toolbox/workflows/github-el-workflow.sh .
                 ;;
              'd11'|'d12'|'u20'|'u24')
                cp project/toolbox/workflows/github_u20_workflow.sh .
                ;;
            esac
        - name: Extract dependencies
          id: extract_deps
          run: |
            echo "$BUILD_VARS_JSON" | jq -r '.repos[] | select(.name == "${{ github.event.repository.name }}") | .deps[]' > deps.txt
            case  "${{ env.BUILD_OS }}" in
              'u20'|'u24')
                 sed -i '/minor-packages/d' deps.txt
              ;;
            *)
                echo "No specific packages to remove"
              ;;
            esac
            echo "Dependencies:"
            cat deps.txt
        - name: Download artifacts
          run: |
            mkdir -p artifacts
            while IFS= read -r repo; do
              echo "Downloading artifact for $repo"
              run_id=$(echo "$BUILD_VARS_JSON" | jq -r ".buildids | .[\"$repo\"]")
              echo "rund id $run_id"
              gh run download $run_id --repo cs1867/$repo -D artifacts/$repo --name "$repo-${{ env.BUILD_OS  }}"  
              artifact_path="artifacts/$repo"
              pwd
              echo "list artifact path"
              ls -al "$artifact_path"
              case "${{ env.BUILD_OS }}" in
                'ol8'|'el9')
                  mkdir -p artifacts/RPMS
                  echo "copy to the artifacts RPM dir"
                  cp "$artifact_path"/RPMS/*.rpm artifacts/RPMS
                 ;;
                'd11'|'d12'|'u20'|'u24')                
                  mkdir -p artifacts/DEBS
                  echo "copy to the artifacts DEBS dir"
                  cp -r "$artifact_path"/* artifacts/DEBS
                  echo "list artifacts DEBS dir"
                  ls -al artifacts/DEBS/*
                  ;;
              esac
            done < deps.txt
          env:
            GITHUB_TOKEN: ${{ secrets.GIT_ACTIONS }}

        - name: run docker oneshot builder and github-actions-workflow.sh
          run: |
              case "${{ env.BUILD_OS }}" in
                'ol8'|'el9')              
                   curl -s https://raw.githubusercontent.com/perfsonar/docker-oneshot-builder/main/build | sh -s - --run github-el-workflow.sh . '${{ env.BUILD_OS }}'  
                ;;
                'd11'|'d12'|'u20'|'u24')                
                  curl -s https://raw.githubusercontent.com/perfsonar/docker-oneshot-builder/main/build | sh -s - --run github_u20_workflow.sh . '${{ env.BUILD_OS }}'
                ;;
              esac
        - uses: actions/upload-artifact@v3
          with:
            name: ${{ github.event.repository.name }}-${{ env.BUILD_OS }}
            path: unibuild-repo
            retention-days: 5

       
