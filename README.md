# Project Plan: The Zero Trust Vault

**Strategic Objective:** Build a "Zero Trust" microservices ecosystem prototype where security is handled by the infrastructure, identity is centralized, and authorization is decoupled from business logic.

---

## Architecture Overview

* **Human Identity:** Keycloak (OIDC/JWT)
* **Machine Identity:** SPIFFE/SPIRE (SVID/mTLS)
* **Policy Engine:** Open Policy Agent (Rego)
* **Enforcement Plane:** Envoy Proxy
* **Secrets Management:** HashiCorp Vault (via SPIFFE Auth)
* **Observability:** eBPF (Cilium/Hubble)

---

## Project Goals

### Goal 1: Identity & Secretless Bootstrapping

* **Objective:** Eliminate "Secret Zero" (hardcoded passwords).
* **Tasks:**
  * Deploy **Keycloak**; configure `manager` and `employee` roles.
  * Initialize **SPIRE**; attest a "Backend" service based on its Docker/Linux UID.
  * **The CTO Challenge:** Connect SPIRE to **HashiCorp Vault**. Ensure the Backend can only fetch its DB credentials by proving its identity via a SPIFFE SVID.

### Goal 2: The Decoupled Data Plane

* **Objective:** Move network security from the Application code to the Infrastructure.
* **Tasks:**
  * Deploy **Envoy Proxy** as a sidecar for your services.
  * Configure Envoy to handle **mTLS** automatically using certificates from SPIRE.
  * **The CTO Challenge:** Implement "Strict mTLS." Verify that any request without a valid SVID—even from within the network—is dropped before reaching the app.

### Goal 3: Fine-Grained Authorization (Policy-as-Code)

* **Objective:** Move "Who can do what" into a central, versioned engine.
* **Tasks:**
  * Deploy **OPA** as a sidecar.
  * Write a **Rego policy** that validates the Keycloak JWT (User) + SPIFFE ID (Service).
  * **The CTO Challenge:** Implement an Attribute-Based Access Control (ABAC) rule: *"Employees can only access documents if the document's 'Security-Level' is 'Public' AND the request originates from a 'Trusted' internal service."*

### Goal 4: Observability & Governance

* **Objective:** Provide "Board-Level" visibility into the security posture.
* **Tasks:**
  * Use **eBPF (Cilium)** to map all service communications.
  * **The CTO Challenge:** Simulate a lateral movement attack. Use your observability tools to prove that the architecture detected and blocked the unauthorized path at the kernel level.

---

## Blog Framing (CTO Perspective)

**Primary Tagline:** *"Journey into the Mechanics of Zero Trust: A 20-Year Veteran’s Blueprint."*

### Strategic Reflection Points

1. **Organizational Velocity:** Does decoupling policy from code allow teams to ship faster?
2. **Risk Mitigation:** How does rotating certificates every 15 minutes via SPIRE change the conversation about "breach impact"?
3. **Governance:** How does moving to OPA/Rego simplify the "Audit" process for a Fortune 500 company?
