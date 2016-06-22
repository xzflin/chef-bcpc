# bcpc-common Cookbook

This cookbook configures basic configuration elements that are common to
all other BCPC node roles.

## Requirements

This cookbook will probably only run correctly on Ubuntu 14.04.

### Chef

- Chef 12.9.41 or later

## Usage

Just include `bcpc-common` in your node's `run_list`:

```json
{
  "name":"my_node",
  "run_list": [
    "recipe[bcpc-common]"
  ]
}
```
