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

package vertikalapp

import (
	"context"
	"fmt"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
	"sigs.k8s.io/controller-runtime/pkg/source"

	vertikalv1alpha1 "github.com/naptime-dev/vertikal/api/v1alpha1"
)

// VertikalAppReconciler reconciles a VertikalApp object
type VertikalAppReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

//+kubebuilder:rbac:groups=vertikal.naptime.dev,resources=vertikalapps,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=vertikal.naptime.dev,resources=vertikalapps/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=vertikal.naptime.dev,resources=vertikalapps/finalizers,verbs=update
//+kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=core,resources=services,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=core,resources=pods,verbs=get;list;watch

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
func (r *VertikalAppReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	logger.Info("Reconciling VertikalApp", "Request.Namespace", req.Namespace, "Request.Name", req.Name)

	// Fetch the VertikalApp instance
	vertikalApp := &vertikalv1alpha1.VertikalApp{}
	err := r.Get(ctx, req.NamespacedName, vertikalApp)
	if err != nil {
		if errors.IsNotFound(err) {
			// Request object not found, could have been deleted after reconcile request.
			// Return and don't requeue
			logger.Info("VertikalApp resource not found. Ignoring since object must be deleted")
			return ctrl.Result{}, nil
		}
		// Error reading the object - requeue the request.
		logger.Error(err, "Failed to get VertikalApp")
		return ctrl.Result{}, err
	}

	// Check if the deployment already exists, if not create a new one
	found := &appsv1.Deployment{}
	err = r.Get(ctx, types.NamespacedName{Name: vertikalApp.Name, Namespace: vertikalApp.Namespace}, found)
	if err != nil && errors.IsNotFound(err) {
		// Define a new deployment
		dep := r.deploymentForVertikalApp(vertikalApp)
		logger.Info("Creating a new Deployment", "Deployment.Namespace", dep.Namespace, "Deployment.Name", dep.Name)
		err = r.Create(ctx, dep)
		if err != nil {
			logger.Error(err, "Failed to create new Deployment", "Deployment.Namespace", dep.Namespace, "Deployment.Name", dep.Name)
			return ctrl.Result{}, err
		}
		// Deployment created successfully - return and requeue
		return ctrl.Result{Requeue: true}, nil
	} else if err != nil {
		logger.Error(err, "Failed to get Deployment")
		return ctrl.Result{}, err
	}

	// Ensure the deployment size is the same as the spec
	size := vertikalApp.Spec.Size
	if *found.Spec.Replicas != size {
		found.Spec.Replicas = &size
		err = r.Update(ctx, found)
		if err != nil {
			logger.Error(err, "Failed to update Deployment", "Deployment.Namespace", found.Namespace, "Deployment.Name", found.Name)
			return ctrl.Result{}, err
		}
		// Spec updated - return and requeue
		return ctrl.Result{Requeue: true}, nil
	}

	// Check if the service already exists, if not create a new one
	service := &corev1.Service{}
	err = r.Get(ctx, types.NamespacedName{Name: vertikalApp.Name, Namespace: vertikalApp.Namespace}, service)
	if err != nil && errors.IsNotFound(err) {
		// Define a new service
		svc := r.serviceForVertikalApp(vertikalApp)
		logger.Info("Creating a new Service", "Service.Namespace", svc.Namespace, "Service.Name", svc.Name)
		err = r.Create(ctx, svc)
		if err != nil {
			logger.Error(err, "Failed to create new Service", "Service.Namespace", svc.Namespace, "Service.Name", svc.Name)
			return ctrl.Result{}, err
		}
		// Service created successfully - return and requeue
		return ctrl.Result{Requeue: true}, nil
	} else if err != nil {
		logger.Error(err, "Failed to get Service")
		return ctrl.Result{}, err
	}

	// Update the VertikalApp status with the pod names
	// List the pods for this VertikalApp's deployment
	podList := &corev1.PodList{}
	listOpts := []client.ListOption{
		client.InNamespace(vertikalApp.Namespace),
		client.MatchingLabels(labelsForVertikalApp(vertikalApp.Name)),
	}
	if err = r.List(ctx, podList, listOpts...); err != nil {
		logger.Error(err, "Failed to list pods", "VertikalApp.Namespace", vertikalApp.Namespace, "VertikalApp.Name", vertikalApp.Name)
		return ctrl.Result{}, err
	}

	// Count the pods that are ready
	var readyReplicas int32 = 0
	for _, pod := range podList.Items {
		for _, condition := range pod.Status.Conditions {
			if condition.Type == corev1.PodReady && condition.Status == corev1.ConditionTrue {
				readyReplicas++
				break
			}
		}
	}

	// Update status.ReadyReplicas if needed
	if vertikalApp.Status.ReadyReplicas != readyReplicas {
		vertikalApp.Status.ReadyReplicas = readyReplicas
		err := r.Status().Update(ctx, vertikalApp)
		if err != nil {
			logger.Error(err, "Failed to update VertikalApp status")
			return ctrl.Result{}, err
		}
	}

	// Requeue to check status periodically
	return ctrl.Result{RequeueAfter: time.Minute}, nil
}

// deploymentForVertikalApp returns a VertikalApp Deployment object
func (r *VertikalAppReconciler) deploymentForVertikalApp(m *vertikalv1alpha1.VertikalApp) *appsv1.Deployment {
	ls := labelsForVertikalApp(m.Name)
	replicas := m.Spec.Size

	dep := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      m.Name,
			Namespace: m.Namespace,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: &replicas,
			Selector: &metav1.LabelSelector{
				MatchLabels: ls,
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: ls,
				},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{{
						Image: m.Spec.Image,
						Name:  "vertikalapp",
						Ports: []corev1.ContainerPort{{
							ContainerPort: m.Spec.Port,
							Name:          "http",
						}},
					}},
				},
			},
		},
	}
	// Set VertikalApp instance as the owner and controller
	controllerutil.SetControllerReference(m, dep, r.Scheme)
	return dep
}

// serviceForVertikalApp returns a VertikalApp Service object
func (r *VertikalAppReconciler) serviceForVertikalApp(m *vertikalv1alpha1.VertikalApp) *corev1.Service {
	ls := labelsForVertikalApp(m.Name)

	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      m.Name,
			Namespace: m.Namespace,
		},
		Spec: corev1.ServiceSpec{
			Selector: ls,
			Ports: []corev1.ServicePort{{
				Port:       m.Spec.Port,
				TargetPort: intstr.FromInt(int(m.Spec.Port)),
				Name:       "http",
			}},
		},
	}
	// Set VertikalApp instance as the owner and controller
	controllerutil.SetControllerReference(m, svc, r.Scheme)
	return svc
}

// labelsForVertikalApp returns the labels for selecting the resources
// belonging to the given VertikalApp CR name.
func labelsForVertikalApp(name string) map[string]string {
	return map[string]string{"app": "vertikalapp", "vertikalapp_cr": name}
}

// SetupWithManager sets up the controller with the Manager.
func (r *VertikalAppReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&vertikalv1alpha1.VertikalApp{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.Service{}).
		Complete(r)
}
