from abc import ABC, abstractmethod
class SitePlugin(ABC):
    name: str        = "Unknown Site"
    description: str = ""
    version: str     = "1.0"
    domain_keys: list[str] = []
    @abstractmethod
    def search(self, page, movie_name: str, config: dict, check_control=None, log_fn=None) -> str:
        ...
    @abstractmethod
    def get_download_link(self, page, movie_url: str, config: dict, check_control=None, log_fn=None) -> str:
        ...
    @abstractmethod
    def get_bridge_link(self, page, bridge_url: str, config: dict, check_control=None, log_fn=None) -> str:
        ...
    @abstractmethod
    def get_final_link(self, page, vcloud_url: str, config: dict, check_control=None, log_fn=None) -> str:
        ...