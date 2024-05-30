
# if on_prem is true then user should be "0" and the pod_path should be set otherwise both should be empty strings
local on_prem_user(on_prem) =
    if std.asciiLower(on_prem) == "true" then "0" else "";

# if on_prem use the pod patch to mount the determined checkpoint path  
local on_prem_pod_patch(on_prem, det_checkpoint_path) =
    if std.asciiLower(on_prem) == "true" then "[{\"op\": \"add\",\"path\": \"/volumes/-\",\"value\": {\"name\": \"det-checkpoints\",\"hostpath\": {\"path\": \"%s\",\"type\": \"Directory\"}}}, {\"op\": \"add\",\"path\": \"/containers/0/volumeMounts/-\",\"value\": {\"mountPath\": \"/determined_shared_fs\",\"name\": \"det-checkpoints\"}}]" % det_checkpoint_path else "";

local model_branch(model, branch) =
    if branch != "master" then model + "-" + branch
    else model;

local full_name(model_branch, mode) =
    if mode == "prep" then model_branch + "-prep"
    else if mode == "train" then model_branch + "-train"
    else if mode == "deploy" then model_branch + "-deploy";

local finbert_repo(mode) =
    if mode == "prep" then "finbert-data"
    else if mode == "train" then "finbert-prep"
    else if mode == "deploy" then "finbert-train";

local repo(model, model_branch, mode) =
    if model == "finbert" then finbert_repo(mode)
    else if mode == "train" then model + "-data"
    else if mode == "deploy" then model_branch + "-train";

# account for naming inconsistencies in the pdk examples
local examples_path(model) = 
    if model == "finbert" then "sentiment-analysis"
    else model;

# use the output of mode to build stdin for the transform section
local stdin(mode, model, model_branch, pach_project) =
    if mode == "train" then "python train.py --git-url https://git@github.com:/bosterbuhr/pdk.git --git-ref main --sub-dir examples/%(examples_path)s/experiment --config const.yaml --repo %(repo)s --model %(name)s --project %(pach_project)s" % {name: model, repo: repo(model, model_branch, mode), examples_path: examples_path(model), pach_project: pach_project}
    else if mode == "deploy" then "python deploy.py --deployment-name %s --service-account-name pach-deploy --resource-requests cpu=1,memory=1Gi --resource-limits cpu=1,memory=1Gi" % full_name(model, mode)
    else if mode == "prep" then "python datasets.py --input_dir /pfs/data --output_dir /pfs/out";

# add boolean parameter handling for autoscaling
local autoscaling_check(autoscaling) =
    if std.asciiLower(autoscaling) == "t" then true else false;

# images not yet available
local pdk_image(model, mode) = 
    if mode == "prep" then "us-central1-docker.pkg.dev/dai-dev-554/pdk-registry/pdk_model_prep:1.0"
    else if mode == "train" then "bosterbuhrhpe/pdk-train:0.2.0"
    else if mode == "deploy" then "pachyderm/pdk:brain-deploy-v0.0.6";


function (model, branch="master", pach_project, on_prem=false, mode, autoscaling="true", det_checkpoint_path="/mnt/efs/shared_fs/determined" )
{
  pipeline: {
    name: full_name(model_branch=model_branch(model, branch), mode=mode)
  },
  description: "Detects changed files into a repository and triggers a retraining on that dataset",
  input: {
    pfs: {
      name: "data",
      repo: repo(model=model, model_branch=model_branch(model, branch), mode=mode),
      branch: branch,
      glob: "/",
      empty_files: true
    }
  },
  scheduling_spec: {
    node_selector: {"kubernetes.io/arch": "amd64"}
  },
  determined: {
    workspaces: ["Default"]
  },
  autoscaling: autoscaling_check(autoscaling),
  datum_tries: 1,
  output_branch: branch,
  transform: {
    user : on_prem_user(on_prem),
    cmd: [
      "/bin/sh"
    ],
    stdin: [
        stdin(mode=mode, model=model, model_branch=model_branch(model, branch), pach_project=pach_project)
    ],
    image: pdk_image(model, mode),
    secrets: [
      {
        name: "det-creds",
        key: "determined-username",
        env_var: "DET_USER"
      },
      {
        name: "det-creds",
        key: "determined-password",
        env_var: "DET_PASSWORD"
      }
    ]
  },
  pod_patch: on_prem_pod_patch(on_prem, det_checkpoint_path)
}
