name: single-ls-registration-daemon-workflow

on:

  workflow_dispatch:
    inputs: 
      BUILD_VARS_JSON:
        description: 'Build var json file'
        required: true

  workflow_run:
    workflows: "Create Artifacts and pass runid"
    branches: 'github-workflow'
    types:
      - completed

jobs:

  build-ls-registration-daemon:

     runs-on: ubuntu-latest

     steps:

        - name: Capture start date and time
          id: start_time
          run: echo "start_time=$(date -u)" >> $GITHUB_ENV

        - name: Add start time to build_vars.json
          run: |
            modified_json=$(echo '${{ github.event.inputs.BUILD_VARS_JSON }}' | jq '.buildstats += { "${{ github.event.repository.name }}-start": "${{ env.start_time }}" }' )
            BUILD_VARS_JSON=$(echo "$modified_json" | jq -c '.')
            echo "BUILD_VARS_JSON=$BUILD_VARS_JSON" >> $GITHUB_ENV
            echo "**** next next ****"
            echo "BUILD_VARS_JSON=$BUILD_VARS_JSON"
        - name: Get build vars from input file
          id: extract_build_vars
          run: |
            BUILD_OS=$(echo  "$BUILD_VARS_JSON" | jq -r '.buildstats.OS' )
            BUILD_BRANCH=$(echo  "$BUILD_VARS_JSON" | jq -r '.buildstats.BUILD_BRANCH' )
            BUILD_TYPE=$(echo  "$BUILD_VARS_JSON" | jq -r '.buildstats.BUILD_TYPE' )
            echo "BUILD_OS=$BUILD_OS" >> $GITHUB_ENV 
            echo "BUILD_BRANCH=$BUILD_BRANCH" >> $GITHUB_ENV
            echo "BUILD_TYPE=$BUILD_TYPE" >> $GITHUB_ENV
       
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

        - name: Delete current repo from build
          id: modify_json
          run: |
            modified_json=$(echo "$BUILD_VARS_JSON" | jq 'del(.repos[0])')
            echo "Modified JSON:"
            echo "$modified_json" | jq .
            BUILD_VARS_JSON=$(echo "$modified_json" | jq -c '.')
            echo "BUILD_VARS_JSON=$BUILD_VARS_JSON" >> $GITHUB_ENV
            echo "**** next next ****"
            echo "BUILD_VARS_JSON=$BUILD_VARS_JSON"
        - name: Use modified BUILD_VARS_JSON
          run: |
            echo "Using the modified BUILD_VARS_JSON environment variable:"
            echo "$BUILD_VARS_JSON" | jq .
        - name: Look up the next repo name to build
          id: extract_repo_name
          run: |
            echo "BUILD_VARS_JSON value is: $BUILD_VARS_JSON"
            NEXTREPO=$(echo  "$BUILD_VARS_JSON"  | jq -r '.repos[0].name' )
            echo "NEXTREPO=$NEXTREPO" >> $GITHUB_ENV
        - name: Display NEXTREPO value
          run: echo "The value of NEXTREPO is $NEXTREPO"
        - name: Add GitHub run ID to buildids
          id: add_run_id
          run: |
            GITHUB_RUN_ID=${{ github.run_id }}
            modified_json=$(echo "$BUILD_VARS_JSON"  | jq --arg run_id "$GITHUB_RUN_ID" '.buildids."${{ github.event.repository.name }}" = $run_id' )
            echo "Modified JSON with GitHub run ID:"
            echo "$modified_json" | jq .
            BUILD_VARS_JSON=$(echo "$modified_json" | jq -c '.')
            echo "BUILD_VARS_JSON=$BUILD_VARS_JSON" >> $GITHUB_ENV
            echo "BUILD_VARS_JSON=$BUILD_VARS_JSON"
        - name: Capture end date and time
          id: end_time
          run: echo "end_time=$(date -u)" >> $GITHUB_ENV

        - name: Add end time to build_vars.json
          run: |
            modified_json=$(echo "$BUILD_VARS_JSON" | jq '.buildstats += { "${{ github.event.repository.name }}-end": "${{ env.end_time }}" }' )
            BUILD_VARS_JSON=$(echo "$modified_json" | jq -c '.')
            echo "BUILD_VARS_JSON=$BUILD_VARS_JSON" >> $GITHUB_ENV
            echo "BUILD_VARS_JSON=$BUILD_VARS_JSON"
        - name: Use modified BUILD_VARS_JSON with run id
          run: |
            echo "Using the modified BUILD_VARS_JSON environment variable:"
            echo "$BUILD_VARS_JSON" | jq .
        - name: Pass workflow
          if: env.BUILD_TYPE == 'FULL'
          uses: actions/github-script@v6
          with:
            github-token: ${{ secrets.GIT_ACTIONS }}
            script: |
              await github.rest.actions.createWorkflowDispatch({
              owner: 'cs1867',
              repo: '${{ env.NEXTREPO}}',
              workflow_id: '${{ env.NEXTREPO}}-workflow.yml',
              ref: 'github-workflow',
               inputs: {
              BUILD_VARS_JSON: '${{ env.BUILD_VARS_JSON}}'
              }
              })
