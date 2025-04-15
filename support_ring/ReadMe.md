# Swift Proxy Support Ring Customization

This document outlines a customization to the Swift proxy server that introduces support for a **"support ring"**—an enhancement designed to address 404 errors that may occur during ring rebalancing.

## Problem

During ring rebalancing, objects are migrated from one storage node to another. This can lead to 404 errors due to timing mismatches between object movement and proxy server updates:

- **Before the proxy server is updated** with the new ring, it may receive requests for objects that have already been moved. Since the proxy is still using the old ring, it cannot locate the objects at their new locations, resulting in 404 errors.
- **After the proxy server is updated** with the new ring, it may receive requests for objects that haven't yet been moved. In this case, the proxy (now using the new ring) cannot locate the objects at their original locations, again resulting in 404 errors.

## Solution

To resolve this, a **"support ring"** is introduced. This support ring represents the previous state of the ring before rebalancing began.

If an object is not found using the current (primary) ring, the proxy server will consult the support ring. This allows the proxy to locate and serve objects regardless of whether they have moved to their new location or not, effectively bridging the gap during the transition.

## Implementation

The support ring functionality was implemented through the following changes:

### 1. `swift/common/storage_policy.py`

- **`load_ring` method:** Modified to load both the primary object ring and an optional support ring (named `<ring_name>.support`).
- **`get_object_ring_support` method:** Added to retrieve the support ring for a given storage policy.

### 2. `swift/proxy/controllers/obj.py`

- **`GETorHEAD` method:** Updated to check the support ring if the object is not found in the primary ring. If the object exists in the support ring, it is served to the client.

### 3. `swift/proxy/server.py`

- **`get_object_ring_support` method:** Added to retrieve the support ring from the `POLICIES` object.

## Configuration

No additional configuration is required. The proxy server will automatically load the support ring if it exists in the `swift_dir`.

> If the primary ring is named `object-?.ring.gz`, the corresponding support ring must be named `object-?.support.ring.gz`.

## Benefits

- Prevents 404 errors during ring rebalancing.
- Ensures a seamless experience for clients during object migration.
- Enhances the availability and reliability of the Swift object storage system.

## Notes

- This customization is completely transparent to clients. No client-side changes are required to benefit from the support ring functionality.
- Tested on Swift version **2.29.1 (Yoga)**.
