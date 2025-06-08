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

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// VertikalAppSpec defines the desired state of VertikalApp
type VertikalAppSpec struct {
	// Size is the size of the VertikalApp deployment
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=10
	// +kubebuilder:default=1
	Size int32 `json:"size,omitempty"`

	// Image is the container image to use for the VertikalApp
	// +kubebuilder:validation:Required
	Image string `json:"image"`

	// Port is the port that the application listens on
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=65535
	// +kubebuilder:default=8080
	Port int32 `json:"port,omitempty"`
}

// VertikalAppStatus defines the observed state of VertikalApp
type VertikalAppStatus struct {
	// Conditions represent the latest available observations of an object's state
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// ReadyReplicas is the number of Pods created by the VertikalApp controller that have a Ready condition
	ReadyReplicas int32 `json:"readyReplicas,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status
//+kubebuilder:printcolumn:name="Ready",type="integer",JSONPath=".status.readyReplicas"
//+kubebuilder:printcolumn:name="Size",type="integer",JSONPath=".spec.size"
//+kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// VertikalApp is the Schema for the vertikalapps API
type VertikalApp struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   VertikalAppSpec   `json:"spec,omitempty"`
	Status VertikalAppStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// VertikalAppList contains a list of VertikalApp
type VertikalAppList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []VertikalApp `json:"items"`
}

func init() {
	SchemeBuilder.Register(&VertikalApp{}, &VertikalAppList{})
}
