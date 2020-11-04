# Confidential Emoji.voto

A microservice application that allows users to vote for their favorite emoji,
and tracks votes received on a leaderboard. May the best emoji win.
The application is a fork of [linkerd's emojivoto](https://github.com/BuoyantIO/emojivoto) refactored as a confidential computing application.

The application is composed of the following 3 services:

* [emojivoto-web](emojivoto-web/): Web frontend and REST API
* [emojivoto-emoji-svc](emojivoto-emoji-svc/): gRPC API for finding and listing emoji
* [emojivoto-voting-svc](emojivoto-voting-svc/): gRPC API for voting and leaderboard

Confidential emojivoto is build as a confidential computing application:

* Each service runs in a confidential enclave using [EdgelessRT](https://www.edgeless.systems/)
* The application is distributed, configured, and connected using [EdgelessMesh](https://www.edgeless.systems/)

![Emojivoto Topology](assets/emojivoto-topology.gif "Emojivoto Topology")

## Running

### In Minikube

Deploy the application to Minikube using the Edgeless Mesh.

1. Private repo setup

    ```bash
    tools/private-repo-setup.sh
    ```

1. Deploy emojivoto

    Deploy with [helm](https://helm.sh/docs/intro/install/)

    * If your deploying on a cluster with nodes that support SGX1+FLC (e.g. AKS or minikube + Azure Standard_DC*s)

    ```bash
    helm install -f ./kubernetes/sgx_values.yaml emojivoto ./kubernetes -n emojivoto
    ```

    * Otherwise

    ```bash
    helm install -f ./kubernetes/nosgx_values.yaml emojivoto ./kubernetes -n emojivoto
    ```

1. Pull the configuration and build the manifest

    ```bash
    tools/pull_manifest.sh
    ```

1. Get the Coordinator's address and set the DNS

    ```bash
    . tools/configure_dns.sh
    ```

1. Install the Edgeless Remote Attestation Tool
    1. Check [requirements](https://github.com/edgelesssys/era#requirements)
    2. See [install](https://github.com/edgelesssys/era#install)

1. Verify the Quote and get the Mesh's Root-Certificate
    * If you're running on a cluster with nodes that support SGX1+FLC

        ```bash
        era -c mesh.config -h $EDG_COORDINATOR_ADDR -o mesh.crt
        ```

    * Otherwise

        ```bash
        era -skip-quote -c mesh.config -h $EDG_COORDINATOR_ADDR -o mesh.crt
        ```

1. Set the manifest

    ```bash
    curl --silent --cacert mesh.crt -X POST -H  "Content-Type: application/json" --data-binary @tools/manifest.json "https://$EDG_COORDINATOR_SVC/manifest"
    ```

1. Install Mesh-Certificate in your browser
    * **Warning** Be careful when adding certificates to your browser. We only do this temporarly for the sake of this demo. Make sure you don't use your browser for other activities in the meanwhile and remove the certificate afterwards.
    * Chrome:
        * Go to <chrome://settings/security>
        * Go to `"Manage certificates" > "Import..."`
        * Follow the "Certificate Import Wizard" and import the `mesh.crt` of the previous step as a "Personal" certificate
    * Firefox:
        * Go to `Tools > Options > Advanced > Certificates: View Certificates`
        * Go to `Import...` and select the `mesh.crt` of the previous step

1. Verify the manifest
    * You can verify the manifest on the client-side before using the app:

    ```bash
    tools/check_manifest.sh tools/manifest.json
    ```

1. Use the app!

    ```bash
    minikube -n emojivoto service web-svc
    #Optional
    sudo kubectl -n emojivoto port-forward svc/web-svc 443:443 --address 0.0.0.0
    ```

    * Browse to [https://localhost:30001](https://localhost:30001) or [https://localhost](https://localhost) depending on your port-forwarding choice above.
    * Notes on DNS: If your running emojivoto on a remote machine you can add the machine's DNS name to the emojivoto certificate (e.g. `emojivoto.example.org`):
        * Open the `kubernetes/sgx_values.yaml` or `kubernetes/nosgx_values.yaml` file depending on your type of deployment
        * Add your DNS name to the `hosts` field: 
            * `hosts: "emojivoto.example.org,localhost,web-svc,web-svc.emojivoto,web-svc.emojivoto.svc.cluster.local"`
        * You need to apply your changes with:
            * If your using `kubernetes/sgx_values.yaml` for your deployment:

                ```bash
                helm upgrade -f ./kubernetes/sgx_values.yaml emojivoto ./kubernetes -n emojivoto
                ```

            * Otherwise:

                ```bash
                helm upgrade -f ./kubernetes/nosgx_values.yaml emojivoto ./kubernetes -n emojivoto
                ```

### Generating some traffic

The `VoteBot` service can generate some traffic for you. It votes on emoji
"randomly" as follows:

* It votes for :doughnut: 15% of the time.
* When not voting for :doughnut:, it picks an emoji at random

If you're running the app using the instructions above, the VoteBot will have
been deployed and will start sending traffic to the vote endpoint.

If you'd like to run the bot manually:

```bash
export WEB_HOST=localhost:443 # replace with your web location
go run emojivoto-web/cmd/vote-bot/main.go
```

## Build

```bash
tools/install-dependencies.sh
mkdir -p build && pushd build && cmake .. && make && popd
tools/build_docker.sh
```

## License

Copyright 2020 Buoyant, Inc. All rights reserved.
Copyright 2020 Edgeless Systems GmbH. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
these files except in compliance with the License. You may obtain a copy of the
License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
