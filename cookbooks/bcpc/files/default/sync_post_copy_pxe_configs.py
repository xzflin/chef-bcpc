#!/ur/binpyton
from cobbler import api
from cobbler import utils
from os.path import isdir


def register():
    """This is a post-sync trigger"""
    return '/var/lib/cobbler/triggers/sync/post/*'


def run(api, args, logger):
    """Only handles synchronisation of PXE boot configs; NOT grub"""
    rc = 0
    srcpath = '/var/lib/tftpboot/pxelinux.cfg/'
    # Copy the generated PXE files - BIOS, UEFI
    pxe_cp_command_tmpl = ('rsync --delete -axSH --info=name'
                           ' %s'
                           ' /var/lib/tftpboot/%s/pxelinux.cfg/' )
    if isdir(srcpath):
        logger.info('Copying PXE configs for BIOS')
        pxe_cp_command = pxe_cp_command_tmpl % (srcpath,'bios')
        rc = utils.subprocess_call(logger, pxe_cp_command, shell=True)

        pxe_cp_command = pxe_cp_command_tmpl % (srcpath,'efi64')
        logger.info('Copying PXE configs for UEFI')
        rc += utils.subprocess_call(logger, pxe_cp_command, shell=True)

    return rc
