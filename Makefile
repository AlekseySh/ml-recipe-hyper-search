##### PATHS #####

DATA_DIR?=data
CONFIG_DIR?=config
CODE_DIR?=src
NOTEBOOKS_DIR?=notebooks
RESULTS_DIR?=results

PROJECT_FILES=requirements.txt apt.txt setup.cfg

PROJECT_PATH_STORAGE?=storage:ml-recipe-hyper-search

PROJECT_PATH_ENV?=/ml-recipe-hyper-search

##### JOB NAMES #####

PROJECT_POSTFIX?=ml-recipe-hyper-search

SETUP_JOB?=setup-$(PROJECT_POSTFIX)
DEVELOP_JOB?=develop-$(PROJECT_POSTFIX)
TRAINING_JOB?=training-$(PROJECT_POSTFIX)
JUPYTER_JOB?=jupyter-$(PROJECT_POSTFIX)
TENSORBOARD_JOB?=tensorboard-$(PROJECT_POSTFIX)
FILEBROWSER_JOB?=filebrowser-$(PROJECT_POSTFIX)

##### ENVIRONMENTS #####

BASE_ENV_NAME?=neuromation/base
CUSTOM_ENV_NAME?=image:neuromation-$(PROJECT_POSTFIX)

##### VARIABLES YOU MAY WANT TO MODIFY #####

N_HYPERPARAMETER_JOBS?=3

# Location of your dataset on the platform storage. Example:
# DATA_DIR_STORAGE?=storage:datasets/cifar10
DATA_DIR_STORAGE?=$(PROJECT_PATH_STORAGE)/$(DATA_DIR)

RESULTS_DIR_STORAGE?=$(PROJECT_PATH_STORAGE)/$(RESULTS_DIR)
RESULTS_DIR_ENV?=$(PROJECT_PATH_ENV)/$(RESULTS_DIR)

# The type of the training machine (run `neuro config show` to see the list of available types).
PRESET?=gpu-small

# HTTP authentication (via cookies) for the job's HTTP link.
# Set `HTTP_AUTH?=--no-http-auth` to disable any authentication.
# WARNING: removing authentication might disclose your sensitive data stored in the job.
HTTP_AUTH?=--http-auth

# Command to run training inside the environment. Example:
# --no-wait-start / -wait-start
WAITING_TRAINING_JOB_START=--wait-start
TRAINING_COMMAND="bash -c 'cd $(PROJECT_PATH_ENV) && python -u $(CODE_DIR)/train.py'"

LOCAL_PORT?=2211

##### SECRETS ######

# Google Cloud integration settings:
GCP_SECRET_FILE?=neuro-job-key.json

GCP_SECRET_PATH_LOCAL=${CONFIG_DIR}/${GCP_SECRET_FILE}
GCP_SECRET_PATH_ENV=${PROJECT_PATH_ENV}/${GCP_SECRET_PATH_LOCAL}

# Weights and Biases integration settings:
WANDB_SECRET_FILE?=wandb-token.txt

WANDB_SECRET_PATH_LOCAL=${CONFIG_DIR}/${WANDB_SECRET_FILE}
WANDB_SECRET_PATH_ENV=${PROJECT_PATH_ENV}/${WANDB_SECRET_PATH_LOCAL}

##### COMMANDS #####

APT?=apt-get -qq
PIP?=pip install --progress-bar=off
NEURO?=neuro


# Check if GCP authentication file exists, then set up variables
ifneq ($(wildcard ${GCP_SECRET_PATH_LOCAL}),)
	OPTION_GCP_CREDENTIALS=\
		--env GOOGLE_APPLICATION_CREDENTIALS=${GCP_SECRET_PATH_ENV} \
		--env GCP_SERVICE_ACCOUNT_KEY_PATH=${GCP_SECRET_PATH_ENV}
else
	OPTION_GCP_CREDENTIALS=
endif

# Check if Weights & Biases key file exists, then set up variables
ifneq ($(wildcard ${WANDB_SECRET_PATH_LOCAL}),)
	OPTION_WANDB_CREDENTIALS=--env NM_WANDB_TOKEN_PATH=${WANDB_SECRET_PATH_ENV}
else
	OPTION_WANDB_CREDENTIALS=
endif

##### HELP #####

.PHONY: help
help:
	@# generate help message by parsing current Makefile
	@# idea: https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
	@grep -hE '^[a-zA-Z_-]+:[^#]*?### .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

##### SETUP #####

.PHONY: setup
setup: ### Setup remote environment
	$(NEURO) kill $(SETUP_JOB) >/dev/null 2>&1
	$(NEURO) run \
		--name $(SETUP_JOB) \
		--preset cpu-small \
		--detach \
		--env JOB_TIMEOUT=1h \
		--volume $(PROJECT_PATH_STORAGE):$(PROJECT_PATH_ENV):ro \
		$(BASE_ENV_NAME) \
		'sleep infinity'
	$(NEURO) mkdir $(PROJECT_PATH_STORAGE) | true
	$(NEURO) mkdir $(PROJECT_PATH_STORAGE)/$(CODE_DIR) | true
	$(NEURO) mkdir $(DATA_DIR_STORAGE) | true
	$(NEURO) mkdir $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR) | true
	$(NEURO) mkdir $(PROJECT_PATH_STORAGE)/$(NOTEBOOKS_DIR) | true
	for file in $(PROJECT_FILES); do $(NEURO) cp ./$$file $(PROJECT_PATH_STORAGE)/$$file; done
	$(NEURO) exec --no-key-check $(SETUP_JOB) "bash -c 'export DEBIAN_FRONTEND=noninteractive && $(APT) update && cat $(PROJECT_PATH_ENV)/apt.txt | xargs -I % $(APT) install --no-install-recommends % && $(APT) clean && $(APT) autoremove && rm -rf /var/lib/apt/lists/*'"
	$(NEURO) exec --no-key-check $(SETUP_JOB) "bash -c '$(PIP) -r $(PROJECT_PATH_ENV)/requirements.txt'"
	$(NEURO) --network-timeout 300 job save $(SETUP_JOB) $(CUSTOM_ENV_NAME)
	$(NEURO) kill $(SETUP_JOB)
	@touch .setup_done

.PHONY: kill-setup
kill-setup:  ### Terminate the setup job (if it was not killed by `make setup` itself)
	$(NEURO) kill $(SETUP_JOB)

.PHONY: _check_setup
_check_setup:
	@test -f .setup_done || { echo "Please run 'make setup' first"; false; }

##### STORAGE #####

.PHONY: upload-code
upload-code: _check_setup  ### Upload code directory to the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(CODE_DIR) $(PROJECT_PATH_STORAGE)/$(CODE_DIR)

.PHONY: clean-code
clean-code: _check_setup  ### Delete code directory from the platform storage
	$(NEURO) rm --recursive $(PROJECT_PATH_STORAGE)/$(CODE_DIR)/*

.PHONY: upload-data
upload-data: _check_setup  ### Upload data directory to the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(DATA_DIR) $(DATA_DIR_STORAGE)

.PHONY: clean-data
clean-data: _check_setup  ### Delete data directory from the platform storage
	$(NEURO) rm --recursive $(DATA_DIR_STORAGE)/*

.PHONY: clean-results
clean-results: _check_setup ### Delete results directory from the platform storage
	$(NEURO) rm --recursive $(RESULTS_DIR_STORAGE)/*

.PHONY: upload-config
upload-config: _check_setup  ### Upload config directory to the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(CONFIG_DIR) $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR)

.PHONY: clean-config
clean-config: _check_setup  ### Delete config directory from the platform storage
	$(NEURO) rm --recursive $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR)/*

.PHONY: upload-notebooks
upload-notebooks: _check_setup  ### Upload notebooks directory to the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(NOTEBOOKS_DIR) $(PROJECT_PATH_STORAGE)/$(NOTEBOOKS_DIR)

.PHONY: download-notebooks
download-notebooks: _check_setup  ### Download notebooks directory from the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(PROJECT_PATH_STORAGE)/$(NOTEBOOKS_DIR) $(NOTEBOOKS_DIR)

.PHONY: download-results
download-results:  ### Download results directory from the platform storage
	$(NEURO) cp --recursive --update --no-target-directory $(RESULTS_DIR_STORAGE) $(RESULTS_DIR)

.PHONY: clean-notebooks
clean-notebooks: _check_setup  ### Delete notebooks directory from the platform storage
	$(NEURO) rm --recursive $(PROJECT_PATH_STORAGE)/$(NOTEBOOKS_DIR)/*

.PHONY: upload-all
upload-all: upload-code upload-data upload-notebooks  ### Upload code, data, and notebooks directories to the platform storage

.PHONY: clean-all
clean-all: clean-code clean-data clean-config clean-notebooks  ### Delete code, data, config and notebooks directories from the platform storage

##### Google Cloud Integration #####

.PHONY: gcloud-check-auth
gcloud-check-auth:  ### Check if the file containing Google Cloud service account key exists
	@echo "Using variable: GCP_SECRET_FILE='${GCP_SECRET_FILE}'"
	@test "${OPTION_GCP_CREDENTIALS}" \
		&& echo "Google Cloud will be authenticated via service account key file: '$${PWD}/${GCP_SECRET_PATH_LOCAL}'" \
		|| { echo "ERROR: Not found Google Cloud service account key file: '$${PWD}/${GCP_SECRET_PATH_LOCAL}'"; \
			echo "Please save the key file named GCP_SECRET_FILE='${GCP_SECRET_FILE}' to './${CONFIG_DIR}/'"; \
			false; }

##### WandB Integration #####

.PHONY: wandb-check-auth
wandb-check-auth:  ### Check if the file Weights and Biases authentication file exists
	@echo Using variable: WANDB_SECRET_FILE='${WANDB_SECRET_FILE}'
	@test "${OPTION_WANDB_CREDENTIALS}" \
		&& echo "Weights & Biases will be authenticated via key file: '$${PWD}/${WANDB_SECRET_PATH_LOCAL}'" \
		|| { echo "ERROR: Not found Weights & Biases key file: '$${PWD}/${WANDB_SECRET_PATH_LOCAL}'"; \
			echo "Please save the key file named WANDB_SECRET_FILE='${WANDB_SECRET_FILE}' to './${CONFIG_DIR}/'"; \
			false; }

##### JOBS #####

.PHONY: develop
develop: upload-code upload-config upload-notebooks  ### Run a development job
	$(NEURO) run \
		--name $(DEVELOP_JOB) \
		--preset $(PRESET) \
		--detach \
		--volume $(DATA_DIR_STORAGE):$(PROJECT_PATH_ENV)/$(DATA_DIR):ro \
		--volume $(PROJECT_PATH_STORAGE)/$(CODE_DIR):$(PROJECT_PATH_ENV)/$(CODE_DIR):rw \
		--volume $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR):$(PROJECT_PATH_ENV)/$(CONFIG_DIR):ro \
		--volume $(RESULTS_DIR_STORAGE):$(RESULTS_DIR_ENV):rw \
		${OPTION_GCP_CREDENTIALS} \
		${OPTION_WANDB_CREDENTIALS} \
		--env EXPOSE_SSH=yes \
		--env JOB_LIFETIME=1d \
		$(CUSTOM_ENV_NAME) \
		"sleep infinity"

.PHONY: connect-develop
connect-develop:  ### Connect to the remote shell running on the development job
	$(NEURO) exec --no-key-check $(DEVELOP_JOB) bash

.PHONY: logs-develop
logs-develop:  ### Connect to the remote shell running on the development job
	$(NEURO) logs $(DEVELOP_JOB)

.PHONY: port-forward-develop
port-forward-develop:  ### Forward SSH port to localhost for remote debugging
	@test ${LOCAL_PORT} || { echo 'Please set up env var LOCAL_PORT'; false; }
	$(NEURO) port-forward $(DEVELOP_JOB) $(LOCAL_PORT):22

.PHONY: kill-develop
kill-develop:  ### Terminate the development job
	$(NEURO) kill $(DEVELOP_JOB)

.PHONY: train
train: _check_setup upload-code upload-config   ### Run a training job
	$(NEURO) run \
	    $(WAITING_TRAINING_JOB_START) \
		--name $(TRAINING_JOB) \
		--preset $(PRESET) \
		--volume $(DATA_DIR_STORAGE):$(PROJECT_PATH_ENV)/$(DATA_DIR):rw \
		--volume $(PROJECT_PATH_STORAGE)/$(CODE_DIR):$(PROJECT_PATH_ENV)/$(CODE_DIR):ro \
		--volume $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR):$(PROJECT_PATH_ENV)/$(CONFIG_DIR):ro \
		--volume $(RESULTS_DIR_STORAGE):$(RESULTS_DIR_ENV):rw \
		${OPTION_GCP_CREDENTIALS} \
		${OPTION_WANDB_CREDENTIALS} \
		--env PYTHONPATH=$(PROJECT_PATH_ENV) \
		--env EXPOSE_SSH=yes \
		--env JOB_TIMEOUT=0 \
		$(CUSTOM_ENV_NAME) \
		$(TRAINING_COMMAND)

.PHONY: hyper-train
hyper-train: _check_setup    ### Run jobs in parallel for hyperparameters search using W&B
	SWEEP_ID="$(shell wandb sweep $(CODE_DIR)/sweep.yaml | grep 'sweep with ID' | cut -d' ' -f5)" ; \
	echo SWEEP_$$SWEEP_ID ; \
	SWEEP_RESULTS_DIR_STORAGE=$(RESULTS_DIR_STORAGE)/sweep-$$SWEEP_ID ; \
	$(NEURO) mkdir $$SWEEP_RESULTS_DIR_STORAGE | true ; \
	for i_job in $$(seq 1 $(N_HYPERPARAMETER_JOBS)) ; do \
        echo "Starting job #"$$i_job ; \
        make train \
            TRAINING_COMMAND="\"bash -c 'cd $(PROJECT_PATH_ENV)/$(CODE_DIR) && wandb agent $$SWEEP_ID'\"" \
            TRAINING_JOB=$(TRAINING_JOB)-$$i_job \
            WAITING_TRAINING_JOB_START=--no-wait-start \
            RESULTS_DIR_STORAGE=$$SWEEP_RESULTS_DIR_STORAGE; \
    done

.PHONY: kill-train
kill-train: _check_setup  ### Terminate the training job
	$(NEURO) kill $(TRAINING_JOB)

.PHONY: kill-hyper-train
kill-hyper-train:  ### Terminate jobs runned for hyper parameters search
	for i_job in $$(seq 1 $(N_HYPERPARAMETER_JOBS)) ; do \
	    make kill-train TRAINING_JOB=$(TRAINING_JOB)-$$i_job ; \
	done

.PHONY: connect-train
connect-train: _check_setup  ### Connect to the remote shell running on the training job
	$(NEURO) exec --no-key-check $(TRAINING_JOB) bash

.PHONY: jupyter
jupyter: _check_setup upload-config upload-code upload-notebooks ### Run a job with Jupyter Notebook and open UI in the default browser
	$(NEURO) run \
		--name $(JUPYTER_JOB) \
		--preset $(PRESET) \
		--http 8888 \
		$(HTTP_AUTH) \
		--browse \
		--detach \
		--env JOB_TIMEOUT=1d \
		--env PYTHONPATH=$(PROJECT_PATH_ENV) \
		${OPTION_GCP_CREDENTIALS} \
		${OPTION_WANDB_CREDENTIALS} \
		--volume $(DATA_DIR_STORAGE):$(PROJECT_PATH_ENV)/$(DATA_DIR):ro \
		--volume $(PROJECT_PATH_STORAGE)/$(CODE_DIR):$(PROJECT_PATH_ENV)/$(CODE_DIR):rw \
		--volume $(PROJECT_PATH_STORAGE)/$(CONFIG_DIR):$(PROJECT_PATH_ENV)/$(CONFIG_DIR):ro \
		--volume $(PROJECT_PATH_STORAGE)/$(NOTEBOOKS_DIR):$(PROJECT_PATH_ENV)/$(NOTEBOOKS_DIR):rw \
		--volume $(RESULTS_DIR_STORAGE):$(RESULTS_DIR_ENV):rw \
		$(CUSTOM_ENV_NAME) \
		'jupyter notebook --no-browser --ip=0.0.0.0 --allow-root --NotebookApp.token= --notebook-dir=$(PROJECT_PATH_ENV)'

.PHONY: kill-jupyter
kill-jupyter: _check_setup  ### Terminate the job with Jupyter Notebook
	$(NEURO) kill $(JUPYTER_JOB)

.PHONY: tensorboard
tensorboard: _check_setup  ### Run a job with TensorBoard and open UI in the default browser
	$(NEURO) run \
		--name $(TENSORBOARD_JOB) \
		--preset cpu-small \
		--http 6006 \
		$(HTTP_AUTH) \
		--browse \
		--env JOB_TIMEOUT=1d \
		--volume $(RESULTS_DIR_STORAGE):$(RESULTS_DIR_ENV):ro \
		$(CUSTOM_ENV_NAME) \
		'tensorboard --host=0.0.0.0 --logdir=$(RESULTS_DIR_ENV)'

.PHONY: kill-tensorboard
kill-tensorboard: _check_setup  ### Terminate the job with TensorBoard
	$(NEURO) kill $(TENSORBOARD_JOB)

.PHONY: filebrowser
filebrowser: _check_setup  ### Run a job with File Browser and open UI in the default browser
	$(NEURO) run \
		--name $(FILEBROWSER_JOB) \
		--preset cpu-small \
		--http 80 \
		$(HTTP_AUTH) \
		--browse \
		--env JOB_TIMEOUT=1d \
		--volume $(PROJECT_PATH_STORAGE):/srv:rw \
		filebrowser/filebrowser \
		--noauth

.PHONY: kill-filebrowser
kill-filebrowser: _check_setup  ### Terminate the job with File Browser
	$(NEURO) kill $(FILEBROWSER_JOB)

.PHONY: kill-all
kill-all: kill-train kill-hyper-train kill-jupyter kill-tensorboard kill-filebrowser  ### Terminate all jobs of this project

##### LOCAL #####

.PHONY: setup-local
setup-local: _check_setup  ### Install pip requirements locally
	$(PIP) -r requirements.txt

.PHONY: lint
lint: _check_setup  ### Run static code analysis locally
	flake8 .
	mypy .

##### MISC #####

.PHONY: ps
ps: _check_setup  ### List all running and pending jobs
	$(NEURO) ps
