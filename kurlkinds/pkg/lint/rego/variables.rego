# Copyright 2022 Replicated Inc.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# 	http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
package kurl.installer

# api_base_url allows for overriding the place where the kurl api is hosted.
api_base_url = "https://kurl.sh"

# this rule determines what endpoint we need to reach when fetching add-on versions remotely
# if there is a pre-determined version in input.spec.kurl.installerVersion we go for add-ons
# specific to the informed version.
add_ons_versions_endpoint = url {
        input.spec.kurl.installerVersion != ""
        url := sprintf("%v/installer/version/%v", [api_base_url, input.spec.kurl.installerVersion])
} else = url {
        url := sprintf("%v/installer", [api_base_url])
}

# remote_versions fetches the list of add-on versions from kurl.sh/installer endpoint.
remote_versions = response {
	http.send(
		{
			"url": add_ons_versions_endpoint,
			"method": "get",
			"raise_error": false,
			"headers": {
				"Accept": "application/json"
			}
		},
		response
	)
}

# iterates over the provided array looking for the "latest" string, once it is found then
# the next element in the array is returned ("latest" precedes "actual latest version").
find_latest_version(allversions) = version {
	some i
	v := allversions[i]
	v == "latest"
	version := allversions[i+1]
}

# known_versions gather all add on known versions according to a remote http request. the
# result here is an object where add-on versions are indexed by the add-on name, something
# similar to:
# {
# 	"addon_name": {
#		"latest": "the latest version (eg. 1.19.0)"
#		"versions": [
#			"1.22.0",
#			"1.21.0",
#			"1.20.0",
#			"1.19.0",
#			...
#		]
#	},
#	...
# }
default known_versions = { addon_name: { "versions": versions, "latest": latest } |
	some addon_name
	allversions := remote_versions.body[addon_name]
	versions := [ version | version := allversions[_]; version != "latest" ]
	latest = find_latest_version(allversions)
}
