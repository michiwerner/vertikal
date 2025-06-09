/*
Copyright 2025, Michael Werner (michael@werner.io)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package e2e

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	"sigs.k8s.io/controller-runtime/pkg/client"

	vertikalv1alpha1 "github.com/michiwerner/vertikal/api/v1alpha1"
)

func TestVertikalApp(t *testing.T) {
	// Setup Kubernetes client
	kubeconfig := os.Getenv("KUBECONFIG")
	if kubeconfig == "" {
		kubeconfig = os.Getenv("HOME") + "/.kube/config"
	}

	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	require.NoError(t, err)

	clientset, err := kubernetes.NewForConfig(config)
	require.NoError(t, err)

	// Create a controller-runtime client
	c, err := client.New(config, client.Options{})
	require.NoError(t, err)

	// Create a test namespace
	ns := &corev1.Namespace{
		ObjectMeta: metav1.ObjectMeta{
			Name: "vertikal-test",
		},
	}
	err = c.Create(context.Background(), ns)
	require.NoError(t, err)

	// Cleanup the test namespace after the test
	defer func() {
		err := clientset.CoreV1().Namespaces().Delete(context.Background(), "vertikal-test", metav1.DeleteOptions{})
		if err != nil {
			t.Logf("Failed to delete namespace: %v", err)
		}
	}()

	// Create a VertikalApp CR
	vertikalApp := &vertikalv1alpha1.VertikalApp{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "test-app",
			Namespace: "vertikal-test",
		},
		Spec: vertikalv1alpha1.VertikalAppSpec{
			Size:  2,
			Image: "nginx:latest",
			Port:  80,
		},
	}

	err = c.Create(context.Background(), vertikalApp)
	require.NoError(t, err)

	// Wait for the deployment to be created
	err = wait.PollImmediate(time.Second, time.Minute, func() (bool, error) {
		deployment := &appsv1.Deployment{}
		err := c.Get(context.Background(), types.NamespacedName{Name: "test-app", Namespace: "vertikal-test"}, deployment)
		if err != nil {
			return false, nil
		}
		return true, nil
	})
	require.NoError(t, err, "Deployment was not created")

	// Wait for the service to be created
	err = wait.PollImmediate(time.Second, time.Minute, func() (bool, error) {
		service := &corev1.Service{}
		err := c.Get(context.Background(), types.NamespacedName{Name: "test-app", Namespace: "vertikal-test"}, service)
		if err != nil {
			return false, nil
		}
		return true, nil
	})
	require.NoError(t, err, "Service was not created")

	// Wait for the deployment to have the correct number of replicas
	err = wait.PollImmediate(time.Second, 2*time.Minute, func() (bool, error) {
		deployment := &appsv1.Deployment{}
		err := c.Get(context.Background(), types.NamespacedName{Name: "test-app", Namespace: "vertikal-test"}, deployment)
		if err != nil {
			return false, nil
		}
		return *deployment.Spec.Replicas == 2, nil
	})
	require.NoError(t, err, "Deployment does not have the correct number of replicas")

	// Update the VertikalApp CR to change the size
	vertikalApp.Spec.Size = 3
	err = c.Update(context.Background(), vertikalApp)
	require.NoError(t, err)

	// Wait for the deployment to have the updated number of replicas
	err = wait.PollImmediate(time.Second, 2*time.Minute, func() (bool, error) {
		deployment := &appsv1.Deployment{}
		err := c.Get(context.Background(), types.NamespacedName{Name: "test-app", Namespace: "vertikal-test"}, deployment)
		if err != nil {
			return false, nil
		}
		return *deployment.Spec.Replicas == 3, nil
	})
	require.NoError(t, err, "Deployment does not have the updated number of replicas")

	// Delete the VertikalApp CR
	err = c.Delete(context.Background(), vertikalApp)
	require.NoError(t, err)

	// Wait for the deployment to be deleted
	err = wait.PollImmediate(time.Second, time.Minute, func() (bool, error) {
		deployment := &appsv1.Deployment{}
		err := c.Get(context.Background(), types.NamespacedName{Name: "test-app", Namespace: "vertikal-test"}, deployment)
		if err != nil {
			if client.IgnoreNotFound(err) == nil {
				return true, nil
			}
			return false, err
		}
		return false, nil
	})
	require.NoError(t, err, "Deployment was not deleted")

	// Wait for the service to be deleted
	err = wait.PollImmediate(time.Second, time.Minute, func() (bool, error) {
		service := &corev1.Service{}
		err := c.Get(context.Background(), types.NamespacedName{Name: "test-app", Namespace: "vertikal-test"}, service)
		if err != nil {
			if client.IgnoreNotFound(err) == nil {
				return true, nil
			}
			return false, err
		}
		return false, nil
	})
	require.NoError(t, err, "Service was not deleted")

	fmt.Println("E2E test completed successfully")
}
