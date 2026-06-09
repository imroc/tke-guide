# E2E Testing

## Overview

Cilium initially used the Ginkgo framework for e2e testing, as described in [End-To-End Testing Framework (Legacy)](https://docs.cilium.io/en/stable/contributing/testing/e2e_legacy/). Later, e2e testing was integrated into cilium-cli. This article explains how to use cilium-cli to run Cilium e2e tests on an existing Kubernetes cluster to verify whether Cilium is functioning correctly in the current environment.

## Test Methods

First, ensure the TKE cluster is located overseas to avoid issues pulling test container images. Then make sure Cilium is installed in the TKE cluster and the nodes have public network access. After that, run the following commands:

- `cilium connectivity test`: Used to verify whether Cilium's features work correctly in the current environment. It runs e2e tests based on the current Cilium configuration (some tests are skipped if certain conditions are not met, e.g., Egress Gateway tests are skipped when the feature is not enabled). The process deploys test Pods in the cluster, runs e2e test cases, collects results, and outputs a summary to the command line. Running all tests takes a considerable amount of time, so patience is required.
- `cilium connectivity perf`: Used to perform performance stress tests on Cilium in the current environment.

## References

- [End-To-End Connectivity Testing](https://docs.cilium.io/en/stable/contributing/testing/e2e/)
