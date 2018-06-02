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
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	logrus "github.com/Sirupsen/logrus"
	"github.com/parnurzeal/gorequest"
)

// esproxy version
const (
	version = "v1.0.0"
)

// check elasticsearch cluster health
func clusterHealth(esServer string) gorequest.Response {
	pathinfo := "health"
	request := RestAPIRequest{method: "get", api: "_cluster", pathinfo: pathinfo}
	resp, body, errs := doRestAPI(esServer, &request)

	if errs != nil {
		logrus.Println(body)
		logrus.Fatal("Error attempting to get cluster health: ", errs)
	}

	return resp
}

// check elasticsearch cluster version
func versionCheck(esServer string) gorequest.Response {
	pathinfo := "/"
	request := RestAPIRequest{method: "get", pathinfo: pathinfo}
	resp, body, errs := doRestAPI(esServer, &request)

	if errs != nil {
		logrus.Println(body)
		logrus.Fatal("Error attempting to get cluster version: ", errs)
	}

	return resp
}

// copy http.Header
func copyHeader(dst, src http.Header) {
	for k, vv := range src {
		for _, v := range vv {
			dst.Add(k, v)
		}
	}
}

func main() {
	logrus.Println("Validating the elasticsearch cluster on prem...")

	esServer := os.Getenv("ES_SERVER")

	if esServer == "" {
		logrus.Println("ES_SERVER is not set, use default")
		esServer = defaultESServer
	}

	// proxy health check
	http.HandleFunc("/es_health", func(w http.ResponseWriter, r *http.Request) {
		resp := clusterHealth(esServer)
		copyHeader(w.Header(), resp.Header)
		w.WriteHeader(http.StatusOK)
		io.Copy(w, resp.Body)
		defer resp.Body.Close()
	})
	// proxy version check
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		resp := versionCheck(esServer)
		copyHeader(w.Header(), resp.Header)
		w.WriteHeader(http.StatusOK)
		io.Copy(w, resp.Body)
		defer resp.Body.Close()
	})

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "ok")
	})

	http.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "ready")
	})

	http.HandleFunc("/version", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, version)
	})

	s := http.Server{Addr: ":9200"}
	go func() {
		logrus.Fatal(s.ListenAndServe())
	}()

	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan, syscall.SIGINT, syscall.SIGTERM)
	<-signalChan

	logrus.Println("Shutdown signal received, exiting...")

	s.Shutdown(context.Background())
}
