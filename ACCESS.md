# Give someone access to an existing rig

Operators can start, stop, check, tunnel to, and open SSM shells on the two
instances. They cannot change or destroy the OpenTofu infrastructure.

## Owner

OpenTofu creates the IAM group `sccache-rig-operators` and attaches everything
needed for `aws login` and `./rig`.

In the AWS console:

1. Open **IAM → Users → Create user**.
2. Give the collaborator their own console login and require a password reset.
3. Add the user to **sccache-rig-operators**.
4. Send them the account sign-in URL and username; do not create or share an
   access key.
5. Have them configure MFA during their first console login.

This grants operational control inside both EC2 instances, including an SSM
shell. Remove the user from the group to revoke rig access.

## Operator

On macOS:

```bash
brew install awscli
brew install --cask session-manager-plugin

git clone <repository-url> sccache-me-outside
cd sccache-me-outside

aws login --profile farm
./rig status
./rig up
./rig shell
```
