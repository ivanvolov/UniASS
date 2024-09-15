package types

import (
	"errors"

	cstaskmanager "github.com/Layr-Labs/incredible-squaring-avs/contracts/bindings/UniASSTaskManager"
)

type TaskResponseData struct {
	TaskResponse              cstaskmanager.IUniASSTaskManagerTaskResponse
	TaskResponseMetadata      cstaskmanager.IUniASSTaskManagerTaskResponseMetadata
	NonSigningOperatorPubKeys []cstaskmanager.BN254G1Point
}

var (
	NoErrorInTaskResponse = errors.New("100. Task response is valid")
)
