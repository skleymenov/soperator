package rest

import (
	"errors"

	appsv1 "k8s.io/api/apps/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	slurmv1 "nebius.ai/slurm-operator/api/v1"
	"nebius.ai/slurm-operator/internal/consts"
	"nebius.ai/slurm-operator/internal/naming"
	"nebius.ai/slurm-operator/internal/render/common"
	"nebius.ai/slurm-operator/internal/values"
)

func RenderDeploymentREST(
	clusterName,
	namespace string,
	valuesREST *values.SlurmREST,
	nodeFilter []slurmv1.K8sNodeFilter,
) (deployment *appsv1.Deployment, err error) {
	if valuesREST == nil || !valuesREST.Enabled {
		return nil, errors.New("REST API is not enabled")
	}
	if valuesREST.ContainerREST.Image == "" {
		return nil, errors.New("image for ContainerREST is empty")
	}

	labels := common.RenderLabels(consts.ComponentTypeREST, clusterName)
	matchLabels := common.RenderMatchLabels(consts.ComponentTypeREST, clusterName)

	podTemplate, err := BasePodTemplateSpec(
		clusterName,
		valuesREST,
		nodeFilter,
		matchLabels,
	)
	if err != nil {
		return nil, err
	}

	// in Deployment mode replicas should be 1.
	// in StatefulSet mode replicas should be more than 1.
	// Because of munge container use pvcs, we can't use template pvc for munge in Deployment mode.
	replicas := int32(1)

	return &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      naming.BuildDeploymentName(consts.ComponentTypeREST),
			Namespace: namespace,
			Labels:    labels,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: &replicas,
			Strategy: appsv1.DeploymentStrategy{
				Type: appsv1.RecreateDeploymentStrategyType,
			},
			Selector: &metav1.LabelSelector{
				MatchLabels: matchLabels,
			},
			Template: *podTemplate,
		},
	}, nil
}
