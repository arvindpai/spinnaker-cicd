/*
Copyright 2018 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"

	logrus "github.com/Sirupsen/logrus"
	"github.com/parnurzeal/gorequest"
)

const (
	GetMethod       string = "get"
	PostMethod      string = "post"
	PutMethod       string = "put"
	DeleteMethod    string = "delete"
	defaultESServer        = "localhost"
	defaultESPort          = 9200
)

type RestAPIRequest struct {
	method   string
	api      string
	pathinfo string
	payload  string
}

func doRestAPI(esServer string, apiRequest *RestAPIRequest) (resp gorequest.Response, body string, errs []error) {

	esURL := fmt.Sprintf("http://%s:%d/%s/%s", esServer, defaultESPort, apiRequest.api, apiRequest.pathinfo)
	logrus.Info(esURL)
	request := gorequest.New()

	switch apiRequest.method {
	case GetMethod:
		resp, body, errs = request.Get(esURL).End()
	case PostMethod:
		resp, body, errs = request.Post(esURL).End()
	case PutMethod:
		if apiRequest.payload == "" {
			resp, body, errs = request.Put(esURL).End()
		} else {
			resp, body, errs = request.Put(esURL).Send(apiRequest.payload).End()
		}
	case DeleteMethod:
		resp, body, errs = request.Delete(esURL).End()
	}
	if errs != nil {
		logrus.Error("Error attempting to doRestApi: ", errs)
		return resp, body, errs
	}

	// Non 2XX status code
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := ioutil.ReadAll(resp.Body)
		logrus.Errorf("Error creating snapshot [httpstatus: %d][url: %s] %s", resp.StatusCode, esURL, string(body))
		return resp, string(body), errs
	}

	// log in pretty print
	buf := new(bytes.Buffer)
	json.Indent(buf, []byte(body), "", "  ")
	logrus.Println(buf)

	return resp, body, errs
}
