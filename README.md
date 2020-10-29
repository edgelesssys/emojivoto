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

    ```bash
    kubectl apply -f kubernetes/
    ```

    * If you're not running on a machine capable of doing SGX DCAP Remote Attestation

        ```bash
        kubectl -n emojivoto get cm oe-config -o yaml | sed -e 's|OE_SIMULATION: "0"|OE_SIMULATION: "1"|' | kubectl apply -f -
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
    * If you're running on a machine capable of doing SGX DCAP Remote Attestation

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
        * Open the `kubernetes/web.yml` file
        * Go to the enviornment variable settings in the StatefulSet: spec.template.spec.containers.env
        * Add your DNS name to `EDG_MARBLE_DNS_NAMES`: 
            * `"emojivoto.example.org,web-svc,web-svc.emojivoto,web-svc.emojivoto.svc.cluster.local"`
        * You need to apply your changes with:

            ```bash
            kubectl apply -f kubernetes/
            ```


### Generating some traffic

The `VoteBot` service can generate some traffic for you. It votes on emoji
"randomly" as follows:

- It votes for :doughnut: 15% of the time.
- When not voting for :doughnut:, it picks an emoji at random

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
